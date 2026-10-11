package main

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"sync"
	"time"
)

type result struct {
	name    string
	status  int
	elapsed time.Duration
	err     error
}

type prober struct {
	client *http.Client
}

func newProber(timeout time.Duration) *prober {
	return &prober{client: &http.Client{
		Timeout: timeout,
		// Like the Route 53 health checks this replaces, a redirect counts as up, so a service that redirects to its
		// login page is healthy without the probe needing to follow it.
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}}
}

// probeAll requests every service at once and returns the results sorted by service name. The TLS certificate is
// verified, so an expired certificate counts as down.
func (p *prober) probeAll(ctx context.Context, services map[string]string) []result {
	results := make([]result, 0, len(services))
	var mu sync.Mutex
	var wg sync.WaitGroup
	for name, url := range services {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := p.probe(ctx, name, url)
			mu.Lock()
			results = append(results, r)
			mu.Unlock()
		}()
	}
	wg.Wait()

	sort.Slice(results, func(i, j int) bool { return results[i].name < results[j].name })
	return results
}

func (p *prober) probe(ctx context.Context, name, url string) result {
	start := time.Now()
	r := result{name: name}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		r.err = err
		return r
	}
	req.Header.Set("User-Agent", "elliotpryde-health-probe")

	resp, err := p.client.Do(req)
	r.elapsed = time.Since(start)
	if err != nil {
		r.err = err
		return r
	}
	resp.Body.Close()

	r.status = resp.StatusCode
	if resp.StatusCode < 200 || resp.StatusCode >= 400 {
		r.err = fmt.Errorf("status %d", resp.StatusCode)
	}
	return r
}
