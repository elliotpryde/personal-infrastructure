package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
)

// fakeMetrics returns the latest Up value for each service by position, or no data for nil
type fakeMetrics struct {
	latest []*float64
}

func (f fakeMetrics) GetMetricData(_ context.Context, in *cloudwatch.GetMetricDataInput, _ ...func(*cloudwatch.Options)) (*cloudwatch.GetMetricDataOutput, error) {
	out := &cloudwatch.GetMetricDataOutput{}
	for i, q := range in.MetricDataQueries {
		r := types.MetricDataResult{Id: q.Id}
		if f.latest[i] != nil {
			r.Values = []float64{*f.latest[i]}
		}
		out.MetricDataResults = append(out.MetricDataResults, r)
	}
	return out, nil
}

func snsEvent(t *testing.T, state string) events.SNSEvent {
	t.Helper()
	return alarmEvent(t, "uptime-services-down", state)
}

func alarmEvent(t *testing.T, name, state string) events.SNSEvent {
	t.Helper()
	msg, err := json.Marshal(alarmMessage{
		AlarmName:       name,
		NewStateValue:   state,
		NewStateReason:  "Threshold Crossed",
		StateChangeTime: "2026-10-10T18:04:05.123+0000",
	})
	if err != nil {
		t.Fatal(err)
	}
	return events.SNSEvent{Records: []events.SNSEventRecord{{SNS: events.SNSEntity{TopicArn: "arn:alerts", Message: string(msg)}}}}
}

func TestHandle(t *testing.T) {
	up, down := aws.Float64(1), aws.Float64(0)
	budget := events.SNSEvent{Records: []events.SNSEventRecord{{SNS: events.SNSEntity{
		TopicArn: "arn:cost-guard",
		Subject:  "AWS Budgets: budget-total has exceeded your alert threshold",
		Message:  "AWS Budget Notification ...",
	}}}}
	confirmation := events.SNSEvent{Records: []events.SNSEventRecord{{SNS: events.SNSEntity{
		TopicArn: "arn:alerts",
		Subject:  "Kill switch activated",
		Message:  "Uptime monitoring is paused",
		// how SNS delivers message attributes to Lambda
		MessageAttributes: map[string]any{
			"source":   map[string]any{"Type": "String", "Value": "uptime-kill-switch"},
			"priority": map[string]any{"Type": "String", "Value": "high"},
		},
	}}}}
	tests := []struct {
		name      string
		event     events.SNSEvent
		latest    []*float64
		wantTitle string // empty means nothing is sent
		wantPrio  string
	}{
		{"services down", snsEvent(t, "ALARM"), []*float64{down, up, down}, "Down: a, c", "urgent"},
		{"probe not reporting", snsEvent(t, "ALARM"), []*float64{nil, nil, nil}, "Health probe isn't reporting", "high"},
		{"recovered before notifying", snsEvent(t, "ALARM"), []*float64{up, up, up}, "Uptime alarm", "high"},
		{"recovered", snsEvent(t, "OK"), nil, "All services up", "default"},
		{"insufficient data", snsEvent(t, "INSUFFICIENT_DATA"), nil, "", ""},
		{"kill switch failed", alarmEvent(t, "uptime-kill-switch-errors", "ALARM"), nil, "uptime-kill-switch-errors", "high"},
		{"kill switch recovered", alarmEvent(t, "uptime-kill-switch-errors", "OK"), nil, "uptime-kill-switch-errors is OK", "default"},
		{"budget exceeded", budget, nil, "Kill switch triggered", "high"},
		{"kill switch confirmation", confirmation, nil, "Kill switch activated", "high"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var got http.Header
			var body string
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				got = r.Header
				b, _ := io.ReadAll(r.Body)
				body = string(b)
			}))
			defer srv.Close()

			n := notifier{
				ntfyURL:        srv.URL + "/topic",
				client:         srv.Client(),
				namespace:      "Test",
				services:       []string{"a", "b", "c"},
				servicesAlarm:  "uptime-services-down",
				costGuardTopic: "arn:cost-guard",
				metrics:        fakeMetrics{latest: tt.latest},
			}
			if err := n.handle(context.Background(), tt.event); err != nil {
				t.Fatal(err)
			}

			if tt.wantTitle == "" {
				if got != nil {
					t.Fatalf("sent %q, want nothing sent", got.Get("Title"))
				}
				return
			}
			if got == nil {
				t.Fatal("nothing sent")
			}
			if got.Get("Title") != tt.wantTitle || got.Get("Priority") != tt.wantPrio {
				t.Errorf("sent title %q priority %q, want %q %q", got.Get("Title"), got.Get("Priority"), tt.wantTitle, tt.wantPrio)
			}
			if body == "" {
				t.Error("sent an empty body")
			}
		})
	}
}

func TestHandleReturnsErrorWhenNtfyFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()

	n := notifier{ntfyURL: srv.URL + "/topic", client: srv.Client()}
	if err := n.handle(context.Background(), snsEvent(t, "OK")); err == nil {
		t.Fatal("got no error, want one so Lambda retries")
	}
}
