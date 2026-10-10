package main

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	cwtypes "github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
	awslambda "github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/aws/aws-sdk-go-v2/service/scheduler"
	"github.com/aws/aws-sdk-go-v2/service/scheduler/types"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	ssmtypes "github.com/aws/aws-sdk-go-v2/service/ssm/types"
)

// fakeAWS keeps just enough state to pause and resume
type fakeAWS struct {
	concurrency   map[string]int32 // a missing function has no reserved concurrency
	failFunction  string
	schedule      scheduler.GetScheduleOutput
	actions       bool
	state         string
	published     []sns.PublishInput
	updateCount   int
	describeCount int
}

func newFake() *fakeAWS {
	return &fakeAWS{
		concurrency: map[string]int32{},
		schedule: scheduler.GetScheduleOutput{
			Name:               aws.String("probe"),
			GroupName:          aws.String("default"),
			ScheduleExpression: aws.String("rate(1 minute)"),
			FlexibleTimeWindow: &types.FlexibleTimeWindow{Mode: types.FlexibleTimeWindowModeOff},
			Target:             &types.Target{Arn: aws.String("arn:function"), RoleArn: aws.String("arn:role")},
			State:              types.ScheduleStateEnabled,
		},
		actions: true,
		state:   stateActive,
	}
}

// resume does what a Terraform apply does to undo a pause
func (f *fakeAWS) resume() {
	f.concurrency = map[string]int32{}
	f.schedule.State = types.ScheduleStateEnabled
	f.actions = true
}

func (f *fakeAWS) PutFunctionConcurrency(_ context.Context, in *awslambda.PutFunctionConcurrencyInput, _ ...func(*awslambda.Options)) (*awslambda.PutFunctionConcurrencyOutput, error) {
	if *in.FunctionName == f.failFunction {
		return nil, errors.New("boom")
	}
	f.concurrency[*in.FunctionName] = *in.ReservedConcurrentExecutions
	return &awslambda.PutFunctionConcurrencyOutput{}, nil
}

func (f *fakeAWS) GetFunctionConcurrency(_ context.Context, in *awslambda.GetFunctionConcurrencyInput, _ ...func(*awslambda.Options)) (*awslambda.GetFunctionConcurrencyOutput, error) {
	out := &awslambda.GetFunctionConcurrencyOutput{}
	if c, ok := f.concurrency[*in.FunctionName]; ok {
		out.ReservedConcurrentExecutions = aws.Int32(c)
	}
	return out, nil
}

func (f *fakeAWS) GetSchedule(context.Context, *scheduler.GetScheduleInput, ...func(*scheduler.Options)) (*scheduler.GetScheduleOutput, error) {
	s := f.schedule
	return &s, nil
}

func (f *fakeAWS) UpdateSchedule(_ context.Context, in *scheduler.UpdateScheduleInput, _ ...func(*scheduler.Options)) (*scheduler.UpdateScheduleOutput, error) {
	f.updateCount++
	// UpdateSchedule replaces the schedule, so the rest of it has to be kept
	if *in.ScheduleExpression != "rate(1 minute)" || *in.Target.Arn != "arn:function" || in.FlexibleTimeWindow == nil {
		return nil, errors.New("schedule not preserved")
	}
	f.schedule.State = in.State
	return &scheduler.UpdateScheduleOutput{}, nil
}

func (f *fakeAWS) DisableAlarmActions(context.Context, *cloudwatch.DisableAlarmActionsInput, ...func(*cloudwatch.Options)) (*cloudwatch.DisableAlarmActionsOutput, error) {
	f.actions = false
	return &cloudwatch.DisableAlarmActionsOutput{}, nil
}

func (f *fakeAWS) DescribeAlarms(context.Context, *cloudwatch.DescribeAlarmsInput, ...func(*cloudwatch.Options)) (*cloudwatch.DescribeAlarmsOutput, error) {
	f.describeCount++
	return &cloudwatch.DescribeAlarmsOutput{MetricAlarms: []cwtypes.MetricAlarm{{ActionsEnabled: aws.Bool(f.actions)}}}, nil
}

func (f *fakeAWS) GetParameter(context.Context, *ssm.GetParameterInput, ...func(*ssm.Options)) (*ssm.GetParameterOutput, error) {
	return &ssm.GetParameterOutput{Parameter: &ssmtypes.Parameter{Value: aws.String(f.state)}}, nil
}

func (f *fakeAWS) PutParameter(_ context.Context, in *ssm.PutParameterInput, _ ...func(*ssm.Options)) (*ssm.PutParameterOutput, error) {
	f.state = *in.Value
	return &ssm.PutParameterOutput{}, nil
}

func (f *fakeAWS) Publish(_ context.Context, in *sns.PublishInput, _ ...func(*sns.Options)) (*sns.PublishOutput, error) {
	f.published = append(f.published, *in)
	return &sns.PublishOutput{}, nil
}

func newKillSwitch(f *fakeAWS) killSwitch {
	return killSwitch{
		functions:      []string{"a", "b"},
		schedule:       "probe",
		alarm:          "down",
		stateParameter: "/state",
		alertsTopic:    "arn:alerts",
		lambda:         f,
		scheduler:      f,
		alarms:         f,
		params:         f,
		topics:         f,
	}
}

func invoke(t *testing.T, k killSwitch, event any) (string, error) {
	t.Helper()
	raw, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	return k.handle(context.Background(), raw)
}

func trigger(subject string) events.SNSEvent {
	return events.SNSEvent{Records: []events.SNSEventRecord{{SNS: events.SNSEntity{Subject: subject, Message: "{}"}}}}
}

var check = map[string]string{"action": "check"}

func TestPauseAndResume(t *testing.T) {
	f := newFake()
	k := newKillSwitch(f)

	if _, err := invoke(t, k, trigger("ALARM: uptime-status-invocations")); err != nil {
		t.Fatal(err)
	}
	if f.concurrency["a"] != 0 || f.concurrency["b"] != 0 || f.schedule.State != types.ScheduleStateDisabled || f.actions {
		t.Fatalf("not fully paused: %+v", f)
	}
	if f.state != statePaused || len(f.published) != 1 || *f.published[0].Subject != "Kill switch activated" {
		t.Fatalf("activation not confirmed: state %q, published %d", f.state, len(f.published))
	}
	if !strings.Contains(*f.published[0].Message, "uptime-status-invocations") {
		t.Errorf("confirmation doesn't say what triggered it: %q", *f.published[0].Message)
	}
	if src := f.published[0].MessageAttributes["source"].StringValue; src == nil || *src != "uptime-kill-switch" {
		t.Errorf("confirmation has no source attribute")
	}

	// a second trigger while paused doesn't confirm again
	if _, err := invoke(t, k, trigger("budget")); err != nil {
		t.Fatal(err)
	}
	if len(f.published) != 1 {
		t.Errorf("confirmed activation %d times, want once", len(f.published))
	}

	// a check before the apply has undone everything doesn't confirm a resume
	f.concurrency = map[string]int32{"a": 0}
	if got, err := invoke(t, k, check); err != nil || got != "still paused: a, probe schedule, down alarm actions" {
		t.Fatalf("check = %q, %v", got, err)
	}

	f.resume()
	if got, err := invoke(t, k, check); err != nil || got != "resumed" {
		t.Fatalf("check = %q, %v, want resumed", got, err)
	}
	if f.state != stateActive || len(f.published) != 2 || *f.published[1].Subject != "Kill switch deactivated" {
		t.Fatalf("deactivation not confirmed: state %q, published %d", f.state, len(f.published))
	}

	// later applies don't confirm again
	if got, err := invoke(t, k, check); err != nil || got != "not paused" || len(f.published) != 2 {
		t.Errorf("check after resuming = %q, %v, published %d", got, err, len(f.published))
	}
}

func TestCheckWhenNeverPausedDoesNothing(t *testing.T) {
	f := newFake()
	if got, err := invoke(t, newKillSwitch(f), check); err != nil || got != "not paused" {
		t.Fatalf("check = %q, %v", got, err)
	}
	if f.describeCount != 0 || len(f.published) != 0 {
		t.Error("checked or confirmed when it was never paused")
	}
}

func TestLeavesADisabledScheduleAlone(t *testing.T) {
	f := newFake()
	f.schedule.State = types.ScheduleStateDisabled
	if _, err := invoke(t, newKillSwitch(f), trigger("budget")); err != nil {
		t.Fatal(err)
	}
	if f.updateCount != 0 {
		t.Error("updated a schedule that was already disabled")
	}
}

func TestKeepsPausingAfterAFailureAndDoesntConfirm(t *testing.T) {
	f := newFake()
	f.failFunction = "a"

	_, err := invoke(t, newKillSwitch(f), trigger("budget"))
	if err == nil || !strings.Contains(err.Error(), "pausing a: boom") {
		t.Fatalf("got error %v, want one naming the failed step so Lambda retries", err)
	}
	if f.concurrency["b"] != 0 || f.schedule.State != types.ScheduleStateDisabled || f.actions {
		t.Error("stopped pausing after the first failure")
	}
	if f.state != stateActive || len(f.published) != 0 {
		t.Error("confirmed a pause that didn't fully work")
	}
}

func TestRejectsUnknownEvents(t *testing.T) {
	if _, err := invoke(t, newKillSwitch(newFake()), map[string]string{"action": "resume"}); err == nil {
		t.Error("got no error for an unknown event")
	}
}
