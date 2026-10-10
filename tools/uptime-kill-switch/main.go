// uptime-kill-switch pauses uptime monitoring when it costs more than it should. It's triggered from the
// uptime-cost-guard SNS topic by an alarm on uptime-status invocations, or by the monthly budget. It sets the reserved
// concurrency of health-probe and uptime-status to 0, so they're throttled (which isn't billed), and disables the probe
// schedule and the uptime alarm's actions.
//
// Running the Terraform workflow resumes everything, because the plan reverts each of these changes. The workflow then
// invokes this function with {"action": "check"} to confirm it.
//
// It confirms both on the uptime-alerts topic, and records whether it's paused in an SSM parameter, so that a check
// only reports a resume once.
package main

import (
	"context"
	"log/slog"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	awslambda "github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/aws/aws-sdk-go-v2/service/scheduler"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		slog.Error("loading AWS config", "error", err)
		os.Exit(1)
	}

	k := killSwitch{
		functions:      strings.Split(os.Getenv("FUNCTIONS"), ","),
		schedule:       os.Getenv("SCHEDULE_NAME"),
		alarm:          os.Getenv("ALARM_NAME"),
		stateParameter: os.Getenv("STATE_PARAMETER"),
		alertsTopic:    os.Getenv("ALERTS_TOPIC_ARN"),
		lambda:         awslambda.NewFromConfig(cfg),
		scheduler:      scheduler.NewFromConfig(cfg),
		alarms:         cloudwatch.NewFromConfig(cfg),
		params:         ssm.NewFromConfig(cfg),
		topics:         sns.NewFromConfig(cfg),
	}
	lambda.Start(k.handle)
}
