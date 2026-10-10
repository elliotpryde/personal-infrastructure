package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
)

type metricsAPI interface {
	GetMetricData(context.Context, *cloudwatch.GetMetricDataInput, ...func(*cloudwatch.Options)) (*cloudwatch.GetMetricDataOutput, error)
}

type notifier struct {
	ntfyURL   string
	client    *http.Client
	namespace string
	services  []string
	// the alarm whose notifications name the services that are down
	servicesAlarm string
	// messages from this topic trigger the kill switch, see Terraform/uptime-cost-guard.tf
	costGuardTopic string
	metrics        metricsAPI
}

// The parts of a CloudWatch alarm's SNS message this uses
type alarmMessage struct {
	AlarmName       string
	NewStateValue   string
	NewStateReason  string
	StateChangeTime string
}

type notification struct {
	title    string
	body     string
	priority string
	tags     string
}

// handle returns an error if ntfy.sh can't be reached, so Lambda retries the asynchronous invocation
func (n notifier) handle(ctx context.Context, event events.SNSEvent) error {
	for _, record := range event.Records {
		if record.SNS.TopicArn == n.costGuardTopic {
			if err := n.send(ctx, killSwitchTriggeredNotification(record.SNS)); err != nil {
				return err
			}
			continue
		}
		if attribute(record.SNS, "source") == "uptime-kill-switch" {
			if err := n.send(ctx, killSwitchConfirmation(record.SNS)); err != nil {
				return err
			}
			continue
		}

		var alarm alarmMessage
		if err := json.Unmarshal([]byte(record.SNS.Message), &alarm); err != nil {
			return fmt.Errorf("parsing alarm message: %w", err)
		}
		slog.Info("alarm state change", "alarm", alarm.AlarmName, "state", alarm.NewStateValue, "reason", alarm.NewStateReason)

		msg, ok, err := n.compose(ctx, alarm)
		if err != nil {
			return err
		}
		if !ok {
			continue
		}
		if err := n.send(ctx, msg); err != nil {
			return err
		}
	}
	return nil
}

// killSwitchTriggeredNotification describes a message to the cost guard topic. It's either an alarm's JSON or a
// budget's plain text, but both have a subject.
func killSwitchTriggeredNotification(msg events.SNSEntity) notification {
	reason := msg.Subject
	if reason == "" {
		reason = msg.Message
	}
	return notification{
		title: "Kill switch triggered",
		body: "Triggered by: " + reason + "\n\nThe kill switch is pausing the health probe and the uptime-status " +
			"function URL. A confirmation follows once it's done.",
		priority: "high",
		tags:     "money_with_wings",
	}
}

// killSwitchConfirmation passes on the kill switch's own message saying it has paused or resumed
func killSwitchConfirmation(msg events.SNSEntity) notification {
	priority := attribute(msg, "priority")
	if priority == "" {
		priority = "default"
	}
	return notification{title: msg.Subject, body: msg.Message, priority: priority, tags: "money_with_wings"}
}

// attribute returns a string message attribute, or "" if it isn't set
func attribute(msg events.SNSEntity, name string) string {
	a, ok := msg.MessageAttributes[name].(map[string]any)
	if !ok {
		return ""
	}
	v, _ := a["Value"].(string)
	return v
}

func (n notifier) compose(ctx context.Context, alarm alarmMessage) (notification, bool, error) {
	at := alarm.StateChangeTime
	if t, err := time.Parse("2006-01-02T15:04:05.000-0700", alarm.StateChangeTime); err == nil {
		at = t.UTC().Format("15:04 UTC")
	}

	if alarm.AlarmName != n.servicesAlarm {
		return otherAlarmNotification(alarm, at), alarm.NewStateValue != "INSUFFICIENT_DATA", nil
	}

	switch alarm.NewStateValue {
	case "OK":
		return notification{
			title:    "All services up",
			body:     "Every service has passed its health probe since " + at + ".",
			priority: "default",
			tags:     "white_check_mark",
		}, true, nil

	case "ALARM":
		down, reporting, err := n.downServices(ctx)
		if err != nil {
			return notification{}, false, err
		}
		switch {
		case len(down) > 0:
			return notification{
				title:    "Down: " + strings.Join(down, ", "),
				body:     "Failing health probes since " + at + ".",
				priority: "urgent",
				tags:     "rotating_light",
			}, true, nil
		case !reporting:
			return notification{
				title:    "Health probe isn't reporting",
				body:     "No uptime data since " + at + ". Check the health-probe Lambda's logs.",
				priority: "high",
				tags:     "warning",
			}, true, nil
		default:
			// the services came back between the alarm firing and this running
			return notification{
				title:    "Uptime alarm",
				body:     alarm.NewStateReason,
				priority: "high",
				tags:     "warning",
			}, true, nil
		}
	}

	// INSUFFICIENT_DATA only happens briefly when the alarm is created, because missing data counts as breaching
	return notification{}, false, nil
}

// otherAlarmNotification describes any alarm on the uptime-alerts topic other than the services alarm, such as the kill
// switch failing
func otherAlarmNotification(alarm alarmMessage, at string) notification {
	if alarm.NewStateValue == "OK" {
		return notification{
			title:    alarm.AlarmName + " is OK",
			body:     "Recovered at " + at + ".",
			priority: "default",
			tags:     "white_check_mark",
		}
	}
	return notification{
		title:    alarm.AlarmName,
		body:     alarm.NewStateReason,
		priority: "high",
		tags:     "warning",
	}
}

// downServices returns the services whose latest probe in the last 5 minutes failed, and whether the probe reported
// anything at all in that time.
func (n notifier) downServices(ctx context.Context) ([]string, bool, error) {
	end := time.Now()
	queries := make([]types.MetricDataQuery, len(n.services))
	for i, name := range n.services {
		queries[i] = types.MetricDataQuery{
			Id: aws.String(fmt.Sprintf("s%d", i)),
			MetricStat: &types.MetricStat{
				Metric: &types.Metric{
					Namespace:  aws.String(n.namespace),
					MetricName: aws.String("Up"),
					Dimensions: []types.Dimension{{Name: aws.String("Service"), Value: aws.String(name)}},
				},
				Period: aws.Int32(60),
				Stat:   aws.String("Minimum"),
			},
		}
	}

	out, err := n.metrics.GetMetricData(ctx, &cloudwatch.GetMetricDataInput{
		StartTime:         aws.Time(end.Add(-5 * time.Minute)),
		EndTime:           aws.Time(end),
		MetricDataQueries: queries,
		ScanBy:            types.ScanByTimestampDescending,
	})
	if err != nil {
		return nil, false, fmt.Errorf("getting uptime metrics: %w", err)
	}

	var down []string
	reporting := false
	for _, r := range out.MetricDataResults {
		if len(r.Values) == 0 {
			continue
		}
		reporting = true
		var i int
		if _, err := fmt.Sscanf(*r.Id, "s%d", &i); err != nil || i >= len(n.services) {
			continue
		}
		if r.Values[0] == 0 {
			down = append(down, n.services[i])
		}
	}
	sort.Strings(down)
	return down, reporting, nil
}

func (n notifier) send(ctx context.Context, msg notification) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, n.ntfyURL, strings.NewReader(msg.body))
	if err != nil {
		return err
	}
	req.Header.Set("Title", msg.title)
	req.Header.Set("Priority", msg.priority)
	req.Header.Set("Tags", msg.tags)

	resp, err := n.client.Do(req)
	if err != nil {
		return fmt.Errorf("sending to ntfy: %w", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("sending to ntfy: status %d", resp.StatusCode)
	}
	slog.Info("sent notification", "title", msg.title)
	return nil
}
