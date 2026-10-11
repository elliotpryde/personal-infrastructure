package main

import (
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
)

// the chart shows one bar per hour for 7 days
const hours = 7 * 24

type metricsAPI interface {
	GetMetricData(context.Context, *cloudwatch.GetMetricDataInput, ...func(*cloudwatch.Options)) (*cloudwatch.GetMetricDataOutput, error)
}

type series struct {
	name string
	// the fraction of probes that passed in each hour from the start of the chart, or NaN for hours with no data
	hourly [hours]float64
}

// fetch gets each service's hourly average of the Up metric, which is the fraction of probes in that hour that passed.
// It's one GetMetricData call per page, billed per metric requested, so this costs one metric per service.
func fetch(ctx context.Context, api metricsAPI, namespace string, services []string, start, end time.Time) ([]series, error) {
	result := make([]series, len(services))
	queries := make([]types.MetricDataQuery, len(services))
	for i, name := range services {
		result[i].name = name
		for h := range result[i].hourly {
			result[i].hourly[h] = math.NaN()
		}
		queries[i] = types.MetricDataQuery{
			Id: aws.String("s" + strconv.Itoa(i)),
			MetricStat: &types.MetricStat{
				Metric: &types.Metric{
					Namespace:  aws.String(namespace),
					MetricName: aws.String("Up"),
					Dimensions: []types.Dimension{{Name: aws.String("Service"), Value: aws.String(name)}},
				},
				Period: aws.Int32(3600),
				Stat:   aws.String("Average"),
			},
		}
	}

	paginator := cloudwatch.NewGetMetricDataPaginator(api, &cloudwatch.GetMetricDataInput{
		StartTime:         aws.Time(start),
		EndTime:           aws.Time(end),
		MetricDataQueries: queries,
	})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		for _, r := range page.MetricDataResults {
			i, err := strconv.Atoi((*r.Id)[1:])
			if err != nil || i >= len(result) {
				continue
			}
			for j, ts := range r.Timestamps {
				h := int(ts.Sub(start) / time.Hour)
				if h >= 0 && h < hours {
					result[i].hourly[h] = r.Values[j]
				}
			}
		}
	}
	return result, nil
}

// uptime is the mean of the hours with data, or NaN if there are none
func (s series) uptime() float64 {
	sum, n := 0.0, 0
	for _, v := range s.hourly {
		if !math.IsNaN(v) {
			sum += v
			n++
		}
	}
	if n == 0 {
		return math.NaN()
	}
	return sum / float64(n)
}

// The colours are readable on light and dark Dashy themes
const (
	colourUp       = "#2da44e"
	colourDegraded = "#d29922"
	colourDown     = "#cf222e"
	colourNoData   = "#8c959f"
	colourText     = "#8c959f"
)

func barColour(v float64) (string, float64) {
	switch {
	case math.IsNaN(v):
		return colourNoData, 0.35
	case v >= 1:
		return colourUp, 1
	case v >= 0.95:
		return colourDegraded, 1
	default:
		return colourDown, 1
	}
}

func formatUptime(v float64) string {
	switch {
	case math.IsNaN(v):
		return "no data"
	case v >= 1:
		return "100%"
	default:
		// round down, so 99.996% doesn't show as 100%
		return fmt.Sprintf("%.2f%%", math.Floor(v*10000)/100)
	}
}

func render(services []series, updated time.Time) []byte {
	const (
		labelWidth = 120
		barWidth   = 3
		barGap     = 1
		pctWidth   = 70
		rowHeight  = 26
		barHeight  = 18
		footer     = 20
	)
	width := labelWidth + hours*(barWidth+barGap) + pctWidth
	height := len(services)*rowHeight + footer

	var b bytes.Buffer
	fmt.Fprintf(&b, `<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="system-ui, sans-serif" font-size="13" fill="%s">`,
		width, height, width, height, colourText)
	for i, s := range services {
		y := i * rowHeight
		textY := y + barHeight/2 + 5
		fmt.Fprintf(&b, `<text x="0" y="%d">%s</text>`, textY, escape(s.name))
		for h, v := range s.hourly {
			colour, opacity := barColour(v)
			fmt.Fprintf(&b, `<rect x="%d" y="%d" width="%d" height="%d" rx="1" fill="%s" fill-opacity="%g"/>`,
				labelWidth+h*(barWidth+barGap), y, barWidth, barHeight, colour, opacity)
		}
		fmt.Fprintf(&b, `<text x="%d" y="%d" text-anchor="end">%s</text>`, width, textY, formatUptime(s.uptime()))
	}
	fmt.Fprintf(&b, `<text x="0" y="%d" font-size="11">Uptime over the last 7 days, hourly. Updated %s.</text>`,
		height-5, updated.UTC().Format("Mon 15:04 UTC"))
	b.WriteString(`</svg>`)
	return b.Bytes()
}

func escape(s string) string {
	var b bytes.Buffer
	_ = xml.EscapeText(&b, []byte(s))
	return b.String()
}
