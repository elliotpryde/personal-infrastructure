// uptime-status serves an SVG chart of each NAS service's uptime over the last 7 days, one row per service, for Dashy's
// image widget. It runs behind a public function URL, so requests need a secret token in the path:
//
//	https://<function URL>/<token>/uptime.svg
//
// The chart is cached for 15 minutes, which with the function's reserved concurrency of 1 bounds GetMetricData calls.
package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"sort"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

const cacheFor = 15 * time.Minute

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
	sort.Strings(names)

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		slog.Error("loading AWS config", "error", err)
		os.Exit(1)
	}

	param := os.Getenv("ACCESS_TOKEN_PARAMETER")
	out, err := ssm.NewFromConfig(cfg).GetParameter(ctx, &ssm.GetParameterInput{Name: &param, WithDecryption: aws.Bool(true)})
	if err != nil {
		slog.Error("reading the access token", "error", err)
		os.Exit(1)
	}

	s := &server{
		path:      "/" + *out.Parameter.Value + "/uptime.svg",
		namespace: os.Getenv("METRIC_NAMESPACE"),
		services:  names,
		metrics:   cloudwatch.NewFromConfig(cfg),
		now:       time.Now,
	}
	lambda.Start(s.handle)
}

type server struct {
	path      string
	namespace string
	services  []string
	metrics   metricsAPI
	now       func() time.Time

	// Lambda sends one request at a time to each instance, so these don't need a lock
	chart     []byte
	chartTime time.Time
}

func (s *server) handle(ctx context.Context, req events.LambdaFunctionURLRequest) (events.LambdaFunctionURLResponse, error) {
	if req.RequestContext.HTTP.Method != http.MethodGet || subtle.ConstantTimeCompare([]byte(req.RawPath), []byte(s.path)) != 1 {
		return events.LambdaFunctionURLResponse{StatusCode: http.StatusNotFound}, nil
	}

	now := s.now()
	if s.chart == nil || now.Sub(s.chartTime) >= cacheFor {
		start := now.UTC().Truncate(time.Hour).Add(-(hours - 1) * time.Hour)
		series, err := fetch(ctx, s.metrics, s.namespace, s.services, start, now)
		if err != nil {
			slog.Error("fetching uptime", "error", err)
			return events.LambdaFunctionURLResponse{StatusCode: http.StatusBadGateway}, nil
		}
		s.chart = render(series, now)
		s.chartTime = now
	}

	return events.LambdaFunctionURLResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type":  "image/svg+xml",
			"Cache-Control": fmt.Sprintf("max-age=%d", int(cacheFor.Seconds())),
		},
		Body: string(s.chart),
	}, nil
}
