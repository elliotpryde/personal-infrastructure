package main

import (
	"context"
	"encoding/xml"
	"math"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
)

type fakeMetrics struct {
	calls int
	// hours from the start of the chart => value, for the first service only
	values map[int]float64
}

func (f *fakeMetrics) GetMetricData(_ context.Context, in *cloudwatch.GetMetricDataInput, _ ...func(*cloudwatch.Options)) (*cloudwatch.GetMetricDataOutput, error) {
	f.calls++
	out := &cloudwatch.GetMetricDataOutput{}
	for i, q := range in.MetricDataQueries {
		r := types.MetricDataResult{Id: q.Id}
		if i == 0 {
			for h, v := range f.values {
				r.Timestamps = append(r.Timestamps, in.StartTime.Add(time.Duration(h)*time.Hour))
				r.Values = append(r.Values, v)
			}
		}
		out.MetricDataResults = append(out.MetricDataResults, r)
	}
	return out, nil
}

func TestFetchPlacesValuesByHour(t *testing.T) {
	start := time.Date(2026, 10, 3, 19, 0, 0, 0, time.UTC)
	api := &fakeMetrics{values: map[int]float64{0: 1, 100: 0.5, hours - 1: 0}}

	got, err := fetch(context.Background(), api, "Test", []string{"a", "b"}, start, start.Add(hours*time.Hour))
	if err != nil {
		t.Fatal(err)
	}

	a := got[0].hourly
	if a[0] != 1 || a[100] != 0.5 || a[hours-1] != 0 || !math.IsNaN(a[1]) {
		t.Errorf("service a = %v %v %v %v, want 1 0.5 0 NaN", a[0], a[100], a[hours-1], a[1])
	}
	if !math.IsNaN(got[1].uptime()) {
		t.Errorf("service b uptime = %v, want NaN with no data", got[1].uptime())
	}
	if want := 1.5 / 3; got[0].uptime() != want {
		t.Errorf("service a uptime = %v, want %v", got[0].uptime(), want)
	}
}

func TestFormatUptime(t *testing.T) {
	for v, want := range map[float64]string{1: "100%", 0.99996: "99.99%", 0.5: "50.00%", math.NaN(): "no data"} {
		if got := formatUptime(v); got != want {
			t.Errorf("formatUptime(%v) = %q, want %q", v, got, want)
		}
	}
}

func TestRenderIsValidSVG(t *testing.T) {
	s := series{name: `<b>&"wallabag"`}
	for h := range s.hourly {
		s.hourly[h] = math.NaN()
	}
	s.hourly[5] = 1

	svg := render([]series{s}, time.Now())
	d := xml.NewDecoder(strings.NewReader(string(svg)))
	for {
		if _, err := d.Token(); err != nil {
			if err.Error() == "EOF" {
				break
			}
			t.Fatalf("invalid XML: %v", err)
		}
	}
	if n := strings.Count(string(svg), "<rect"); n != hours {
		t.Errorf("got %d bars, want %d", n, hours)
	}
}

func TestHandle(t *testing.T) {
	now := time.Date(2026, 10, 10, 18, 30, 0, 0, time.UTC)
	api := &fakeMetrics{}
	s := &server{
		path:      "/secret/uptime.svg",
		namespace: "Test",
		services:  []string{"a"},
		metrics:   api,
		now:       func() time.Time { return now },
	}
	get := func(path string) events.LambdaFunctionURLResponse {
		var req events.LambdaFunctionURLRequest
		req.RawPath = path
		req.RequestContext.HTTP.Method = http.MethodGet
		resp, err := s.handle(context.Background(), req)
		if err != nil {
			t.Fatal(err)
		}
		return resp
	}

	if resp := get("/wrong/uptime.svg"); resp.StatusCode != http.StatusNotFound {
		t.Errorf("wrong token: status %d, want 404", resp.StatusCode)
	}
	if api.calls != 0 {
		t.Errorf("wrong token fetched metrics")
	}

	resp := get("/secret/uptime.svg")
	if resp.StatusCode != http.StatusOK || resp.Headers["Content-Type"] != "image/svg+xml" {
		t.Errorf("status %d, content type %q, want 200 image/svg+xml", resp.StatusCode, resp.Headers["Content-Type"])
	}

	now = now.Add(cacheFor - time.Second)
	get("/secret/uptime.svg")
	if api.calls != 1 {
		t.Errorf("fetched %d times within the cache period, want 1", api.calls)
	}

	now = now.Add(time.Second)
	get("/secret/uptime.svg")
	if api.calls != 2 {
		t.Errorf("fetched %d times after the cache period, want 2", api.calls)
	}
}
