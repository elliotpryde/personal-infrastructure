// alert-notifier sends uptime alerts to ntfy.sh. It subscribes to two SNS topics:
//   - uptime-alerts: alarm state changes, and the uptime kill switch confirming it has paused or resumed. For the
//     uptime-services-down alarm it names the services that are down.
//   - uptime-cost-guard: messages that trigger the uptime kill switch, from an alarm or the monthly budget.
//
// The ntfy.sh topic is public, so its name is kept secret in SSM Parameter Store.
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	var services map[string]string
	if err := json.Unmarshal([]byte(os.Getenv("SERVICES")), &services); err != nil {
		slog.Error("SERVICES must be a JSON object of service name to URL", "error", err)
		os.Exit(1)
	}
	names := make([]string, 0, len(services))
	for name := range services {
		names = append(names, name)
	}

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		slog.Error("loading AWS config", "error", err)
		os.Exit(1)
	}

	topic, err := getSecureParameter(ctx, ssm.NewFromConfig(cfg), os.Getenv("NTFY_TOPIC_PARAMETER"))
	if err != nil {
		slog.Error("reading the ntfy topic", "error", err)
		os.Exit(1)
	}

	n := notifier{
		ntfyURL:        os.Getenv("NTFY_URL") + "/" + topic,
		client:         &http.Client{Timeout: 10 * time.Second},
		namespace:      os.Getenv("METRIC_NAMESPACE"),
		services:       names,
		servicesAlarm:  os.Getenv("SERVICES_ALARM_NAME"),
		costGuardTopic: os.Getenv("COST_GUARD_TOPIC_ARN"),
		metrics:        cloudwatch.NewFromConfig(cfg),
	}
	lambda.Start(n.handle)
}

func getSecureParameter(ctx context.Context, client *ssm.Client, name string) (string, error) {
	out, err := client.GetParameter(ctx, &ssm.GetParameterInput{Name: &name, WithDecryption: aws.Bool(true)})
	if err != nil {
		return "", err
	}
	return *out.Parameter.Value, nil
}
