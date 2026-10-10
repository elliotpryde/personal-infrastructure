package main

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	awslambda "github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/aws/aws-sdk-go-v2/service/scheduler"
	"github.com/aws/aws-sdk-go-v2/service/scheduler/types"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	snstypes "github.com/aws/aws-sdk-go-v2/service/sns/types"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	ssmtypes "github.com/aws/aws-sdk-go-v2/service/ssm/types"
)

// check runs after every Terraform apply. If the kill switch had paused uptime monitoring and the apply has undone
// every part of the pause, it confirms the resume. It returns a summary for the workflow log.
func (k killSwitch) check(ctx context.Context) (string, error) {
	state, err := k.state(ctx)
	if err != nil {
		return "", err
	}
	if state != statePaused {
		return "not paused", nil
	}

	paused, err := k.stillPaused(ctx)
	if err != nil {
		return "", err
	}
	if len(paused) > 0 {
		slog.Warn("still paused after the apply", "paused", paused)
		return "still paused: " + strings.Join(paused, ", "), nil
	}

	if err := k.transition(ctx, stateActive, "Kill switch deactivated", "default",
		"Uptime monitoring has resumed: "+strings.Join(k.functions, " and ")+" can run, the probe schedule is "+
			"enabled and the uptime alarm's actions are on."); err != nil {
		return "", err
	}
	return "resumed", nil
}

// stillPaused returns the parts of a pause that haven't been undone
func (k killSwitch) stillPaused(ctx context.Context) ([]string, error) {
	var paused []string
	for _, fn := range k.functions {
		c, err := k.lambda.GetFunctionConcurrency(ctx, &awslambda.GetFunctionConcurrencyInput{FunctionName: aws.String(fn)})
		if err != nil {
			return nil, fmt.Errorf("getting %s concurrency: %w", fn, err)
		}
		// nil means no reserved concurrency, which is how Terraform leaves functions with a limit of -1
		if c.ReservedConcurrentExecutions != nil && *c.ReservedConcurrentExecutions == 0 {
			paused = append(paused, fn)
		}
	}

	s, err := k.scheduler.GetSchedule(ctx, &scheduler.GetScheduleInput{Name: aws.String(k.schedule)})
	if err != nil {
		return nil, fmt.Errorf("getting %s schedule: %w", k.schedule, err)
	}
	if s.State != types.ScheduleStateEnabled {
		paused = append(paused, k.schedule+" schedule")
	}

	a, err := k.alarms.DescribeAlarms(ctx, &cloudwatch.DescribeAlarmsInput{AlarmNames: []string{k.alarm}})
	if err != nil {
		return nil, fmt.Errorf("describing %s alarm: %w", k.alarm, err)
	}
	if len(a.MetricAlarms) == 0 || a.MetricAlarms[0].ActionsEnabled == nil || !*a.MetricAlarms[0].ActionsEnabled {
		paused = append(paused, k.alarm+" alarm actions")
	}
	return paused, nil
}

func (k killSwitch) state(ctx context.Context) (string, error) {
	out, err := k.params.GetParameter(ctx, &ssm.GetParameterInput{Name: aws.String(k.stateParameter)})
	if err != nil {
		return "", fmt.Errorf("reading the kill switch state: %w", err)
	}
	return *out.Parameter.Value, nil
}

// transition records the new state, then confirms it on the uptime-alerts topic. The source attribute tells
// alert-notifier it isn't an alarm.
func (k killSwitch) transition(ctx context.Context, state, subject, priority, message string) error {
	if _, err := k.params.PutParameter(ctx, &ssm.PutParameterInput{
		Name:      aws.String(k.stateParameter),
		Value:     aws.String(state),
		Type:      ssmtypes.ParameterTypeString,
		Overwrite: aws.Bool(true),
	}); err != nil {
		return fmt.Errorf("recording the kill switch state: %w", err)
	}

	if _, err := k.topics.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(k.alertsTopic),
		Subject:  aws.String(subject),
		Message:  aws.String(message),
		MessageAttributes: map[string]snstypes.MessageAttributeValue{
			"source":   {DataType: aws.String("String"), StringValue: aws.String("uptime-kill-switch")},
			"priority": {DataType: aws.String("String"), StringValue: aws.String(priority)},
		},
	}); err != nil {
		return fmt.Errorf("confirming %q: %w", subject, err)
	}
	slog.Info("confirmed", "state", state)
	return nil
}
