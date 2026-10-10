package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
)

func TestProbeAll(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/ok", func(w http.ResponseWriter, _ *http.Request) {})
	mux.HandleFunc("/redirect", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/error", http.StatusFound)
	})
	mux.HandleFunc("/error", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusBadGateway) })
	mux.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-time.After(time.Second):
		case <-r.Context().Done():
		}
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	results := newProber(200*time.Millisecond).probeAll(context.Background(), map[string]string{
		"a-ok":       srv.URL + "/ok",
		"b-redirect": srv.URL + "/redirect",
		"c-error":    srv.URL + "/error",
		"d-slow":     srv.URL + "/slow",
		"e-refused":  "http://127.0.0.1:1/",
	})

	want := []struct {
		name string
		up   bool
	}{
		{"a-ok", true},
		{"b-redirect", true}, // not followed, so the 502 behind it doesn't count
		{"c-error", false},
		{"d-slow", false},
		{"e-refused", false},
	}
	if len(results) != len(want) {
		t.Fatalf("got %d results, want %d", len(results), len(want))
	}
	for i, w := range want {
		r := results[i]
		if r.name != w.name || (r.err == nil) != w.up {
			t.Errorf("result %d = %s up=%v (err %v), want %s up=%v", i, r.name, r.err == nil, r.err, w.name, w.up)
		}
	}
}

type fakeMetrics struct {
	input *cloudwatch.PutMetricDataInput
}

func (f *fakeMetrics) PutMetricData(_ context.Context, in *cloudwatch.PutMetricDataInput, _ ...func(*cloudwatch.Options)) (*cloudwatch.PutMetricDataOutput, error) {
	f.input = in
	return &cloudwatch.PutMetricDataOutput{}, nil
}

func TestHandlePutsOneMetricPerServicePlusServicesDown(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {}))
	defer srv.Close()

	m := &fakeMetrics{}
	h := handler{
		namespace: "Test",
		services:  map[string]string{"up": srv.URL, "down": "http://127.0.0.1:1/"},
		prober:    newProber(time.Second),
		metrics:   m,
	}
	if err := h.handle(context.Background()); err != nil {
		t.Fatal(err)
	}

	got := map[string]float64{}
	for _, d := range m.input.MetricData {
		key := *d.MetricName
		if len(d.Dimensions) > 0 {
			key += "/" + *d.Dimensions[0].Value
		}
		got[key] = *d.Value
	}
	want := map[string]float64{"Up/up": 1, "Up/down": 0, "ServicesDown": 1}
	if len(got) != len(want) {
		t.Fatalf("got metrics %v, want %v", got, want)
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %v, want %v", k, got[k], v)
		}
	}
}
