// health-probe requests each NAS service from outside the network and records whether it's up as CloudWatch metrics:
// Up (1 or 0) per service, and ServicesDown, the number of services that failed. It runs every minute from EventBridge
// Scheduler, and the uptime-services-down alarm watches ServicesDown.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	var services map[string]string
	if err := json.Unmarshal([]byte(os.Getenv("SERVICES")), &services); err != nil {
		slog.Error("SERVICES must be a JSON object of service name to URL", "error", err)
		os.Exit(1)
	}

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		slog.Error("loading AWS config", "error", err)
		os.Exit(1)
	}

	h := handler{
		namespace: os.Getenv("METRIC_NAMESPACE"),
		services:  services,
		prober:    newProber(10 * time.Second),
		metrics:   cloudwatch.NewFromConfig(cfg),
	}
	lambda.Start(h.handle)
}

type metricsAPI interface {
	PutMetricData(context.Context, *cloudwatch.PutMetricDataInput, ...func(*cloudwatch.Options)) (*cloudwatch.PutMetricDataOutput, error)
}

type handler struct {
	namespace string
	services  map[string]string
	prober    *prober
	metrics   metricsAPI
}

func (h handler) handle(ctx context.Context) error {
	now := time.Now()
	results := h.prober.probeAll(ctx, h.services)

	data := make([]types.MetricDatum, 0, len(results)+1)
	down := 0
	for _, r := range results {
		up := 1.0
		if r.err != nil {
			up = 0
			down++
			slog.Warn("service down", "service", r.name, "url", h.services[r.name], "error", r.err.Error(), "elapsed_ms", r.elapsed.Milliseconds())
		} else {
			slog.Info("service up", "service", r.name, "status", r.status, "elapsed_ms", r.elapsed.Milliseconds())
		}
		data = append(data, types.MetricDatum{
			MetricName: aws.String("Up"),
			Dimensions: []types.Dimension{{Name: aws.String("Service"), Value: aws.String(r.name)}},
			Timestamp:  aws.Time(now),
			Value:      aws.Float64(up),
			Unit:       types.StandardUnitNone,
		})
	}
	data = append(data, types.MetricDatum{
		MetricName: aws.String("ServicesDown"),
		Timestamp:  aws.Time(now),
		Value:      aws.Float64(float64(down)),
		Unit:       types.StandardUnitCount,
	})

	// one request for every metric keeps PutMetricData well inside the free tier's 1M API requests a month
	if _, err := h.metrics.PutMetricData(ctx, &cloudwatch.PutMetricDataInput{
		Namespace:  aws.String(h.namespace),
		MetricData: data,
	}); err != nil {
		return fmt.Errorf("putting metrics: %w", err)
	}
	return nil
}
