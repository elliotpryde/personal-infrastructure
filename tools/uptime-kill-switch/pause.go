package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	awslambda "github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/aws/aws-sdk-go-v2/service/scheduler"
	"github.com/aws/aws-sdk-go-v2/service/scheduler/types"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

type lambdaAPI interface {
	PutFunctionConcurrency(context.Context, *awslambda.PutFunctionConcurrencyInput, ...func(*awslambda.Options)) (*awslambda.PutFunctionConcurrencyOutput, error)
	GetFunctionConcurrency(context.Context, *awslambda.GetFunctionConcurrencyInput, ...func(*awslambda.Options)) (*awslambda.GetFunctionConcurrencyOutput, error)
}

type schedulerAPI interface {
	GetSchedule(context.Context, *scheduler.GetScheduleInput, ...func(*scheduler.Options)) (*scheduler.GetScheduleOutput, error)
	UpdateSchedule(context.Context, *scheduler.UpdateScheduleInput, ...func(*scheduler.Options)) (*scheduler.UpdateScheduleOutput, error)
}

type alarmsAPI interface {
	DisableAlarmActions(context.Context, *cloudwatch.DisableAlarmActionsInput, ...func(*cloudwatch.Options)) (*cloudwatch.DisableAlarmActionsOutput, error)
	DescribeAlarms(context.Context, *cloudwatch.DescribeAlarmsInput, ...func(*cloudwatch.Options)) (*cloudwatch.DescribeAlarmsOutput, error)
}

type paramsAPI interface {
	GetParameter(context.Context, *ssm.GetParameterInput, ...func(*ssm.Options)) (*ssm.GetParameterOutput, error)
	PutParameter(context.Context, *ssm.PutParameterInput, ...func(*ssm.Options)) (*ssm.PutParameterOutput, error)
}

type topicsAPI interface {
	Publish(context.Context, *sns.PublishInput, ...func(*sns.Options)) (*sns.PublishOutput, error)
}

type killSwitch struct {
	functions      []string
	schedule       string
	alarm          string
	stateParameter string
	alertsTopic    string
	lambda         lambdaAPI
	scheduler      schedulerAPI
	alarms         alarmsAPI
	params         paramsAPI
	topics         topicsAPI
}

const (
	statePaused = "paused"
	stateActive = "active"
)

// event is either an SNS notification from the uptime-cost-guard topic, which pauses, or {"action": "check"} from the
// Terraform workflow
type event struct {
	Records []events.SNSEventRecord
	Action  string `json:"action"`
}

func (k killSwitch) handle(ctx context.Context, raw json.RawMessage) (string, error) {
	var e event
	if err := json.Unmarshal(raw, &e); err != nil {
		return "", fmt.Errorf("parsing event: %w", err)
	}
	switch {
	case e.Action == "check":
		return k.check(ctx)
	case len(e.Records) > 0:
		return "", k.pause(ctx, e.Records)
	default:
		return "", fmt.Errorf("unrecognised event: %s", raw)
	}
}

// pause pauses as much as it can even if a step fails, then returns any errors so Lambda retries, and the
// uptime-kill-switch-errors alarm tells me. Every step is idempotent, so retrying is safe. It only confirms once every
// step has worked, and only the first time.
func (k killSwitch) pause(ctx context.Context, records []events.SNSEventRecord) error {
	var reasons []string
	for _, r := range records {
		reason := r.SNS.Subject
		if reason == "" {
			reason = r.SNS.Message
		}
		reasons = append(reasons, reason)
	}
	reason := strings.Join(reasons, "; ")
	slog.Warn("pausing uptime monitoring", "reason", reason)

	var errs []error
	for _, fn := range k.functions {
		if _, err := k.lambda.PutFunctionConcurrency(ctx, &awslambda.PutFunctionConcurrencyInput{
			FunctionName:                 aws.String(fn),
			ReservedConcurrentExecutions: aws.Int32(0),
		}); err != nil {
			errs = append(errs, fmt.Errorf("pausing %s: %w", fn, err))
		} else {
			slog.Info("paused function", "function", fn)
		}
	}
	if err := k.disableSchedule(ctx); err != nil {
		errs = append(errs, err)
	}
	// otherwise the probe stopping would set the uptime alarm off
	if _, err := k.alarms.DisableAlarmActions(ctx, &cloudwatch.DisableAlarmActionsInput{AlarmNames: []string{k.alarm}}); err != nil {
		errs = append(errs, fmt.Errorf("disabling %s alarm actions: %w", k.alarm, err))
	}
	if len(errs) > 0 {
		return errors.Join(errs...)
	}

	state, err := k.state(ctx)
	if err != nil {
		return err
	}
	if state == statePaused {
		slog.Info("already paused, not confirming again")
		return nil
	}
	return k.transition(ctx, statePaused, "Kill switch activated", "high",
		"Uptime monitoring is paused: "+strings.Join(k.functions, " and ")+" can't run, the probe schedule is "+
			"disabled and the uptime alarm's actions are off.\n\nTriggered by: "+reason+
			"\n\nRun the Terraform workflow to resume.")
}

// disableSchedule disables the probe schedule. UpdateSchedule replaces the whole schedule, so it copies the current one.
func (k killSwitch) disableSchedule(ctx context.Context) error {
	s, err := k.scheduler.GetSchedule(ctx, &scheduler.GetScheduleInput{Name: aws.String(k.schedule)})
	if err != nil {
		return fmt.Errorf("getting %s schedule: %w", k.schedule, err)
	}
	if s.State == types.ScheduleStateDisabled {
		return nil
	}
	if _, err := k.scheduler.UpdateSchedule(ctx, &scheduler.UpdateScheduleInput{
		Name:                       s.Name,
		GroupName:                  s.GroupName,
		ScheduleExpression:         s.ScheduleExpression,
		ScheduleExpressionTimezone: s.ScheduleExpressionTimezone,
		FlexibleTimeWindow:         s.FlexibleTimeWindow,
		Target:                     s.Target,
		Description:                s.Description,
		StartDate:                  s.StartDate,
		EndDate:                    s.EndDate,
		KmsKeyArn:                  s.KmsKeyArn,
		ActionAfterCompletion:      s.ActionAfterCompletion,
		State:                      types.ScheduleStateDisabled,
	}); err != nil {
		return fmt.Errorf("disabling %s schedule: %w", k.schedule, err)
	}
	slog.Info("disabled schedule", "schedule", k.schedule)
	return nil
}
