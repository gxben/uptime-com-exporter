// Copyright 2026 Benjamin Zores
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package collector

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/uptime-com/uptime-client-go/v2/pkg/upapi"
)

const (
	namespace = "uptime"
	pageSize  = int64(100)
)

// Collector implements prometheus.Collector backed by the official uptime.com SDK.
type Collector struct {
	api     upapi.API
	timeout time.Duration

	up               *prometheus.Desc
	paused           *prometheus.Desc
	underMaintenance *prometheus.Desc
	responseTime     *prometheus.Desc
	sslIsMonitored   *prometheus.Desc

	scrapeDuration *prometheus.Desc
	scrapeSuccess  *prometheus.Desc
}

// New returns a Collector ready to register with a Prometheus registry.
func New(api upapi.API, timeout time.Duration) *Collector {
	labels := []string{"pk", "name", "address", "check_type", "tags"}

	desc := func(name, help string) *prometheus.Desc {
		return prometheus.NewDesc(prometheus.BuildFQName(namespace, "check", name), help, labels, nil)
	}

	return &Collector{
		api:     api,
		timeout: timeout,

		up:               desc("up", "1 if the check is currently passing (up and not paused)."),
		paused:           desc("paused", "1 if the check is paused."),
		underMaintenance: desc("under_maintenance", "1 if the check is currently in a maintenance window."),
		responseTime:     desc("response_time_ms", "Most recent cached response time in milliseconds."),
		sslIsMonitored:   desc("ssl_monitored", "1 if this check has an SSL certificate monitoring config attached."),

		scrapeDuration: prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "scrape", "duration_seconds"),
			"Total time spent fetching data from the uptime.com API.", nil, nil,
		),
		scrapeSuccess: prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "scrape", "success"),
			"1 if the last scrape completed without errors.", nil, nil,
		),
	}
}

// Describe implements prometheus.Collector.
func (c *Collector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.up
	ch <- c.paused
	ch <- c.underMaintenance
	ch <- c.responseTime
	ch <- c.sslIsMonitored
	ch <- c.scrapeDuration
	ch <- c.scrapeSuccess
}

// Collect implements prometheus.Collector.
func (c *Collector) Collect(ch chan<- prometheus.Metric) {
	start := time.Now()
	success := 1.0

	if err := c.collect(ch); err != nil {
		slog.Error("scrape failed", "err", err)
		success = 0
	}

	ch <- prometheus.MustNewConstMetric(c.scrapeDuration, prometheus.GaugeValue, time.Since(start).Seconds())
	ch <- prometheus.MustNewConstMetric(c.scrapeSuccess, prometheus.GaugeValue, success)
}

func (c *Collector) collect(ch chan<- prometheus.Metric) error {
	ctx, cancel := context.WithTimeout(context.Background(), c.timeout)
	defer cancel()

	checks, err := c.listAllChecks(ctx)
	if err != nil {
		return err
	}

	for _, check := range checks {
		lv := []string{
			fmt.Sprintf("%d", check.PK),
			check.Name,
			check.Address,
			check.CheckType,
			strings.Join(check.Tags, ","),
		}

		gauge := func(desc *prometheus.Desc, v float64) {
			ch <- prometheus.MustNewConstMetric(desc, prometheus.GaugeValue, v, lv...)
		}
		boolGauge := func(desc *prometheus.Desc, v bool) {
			if v {
				gauge(desc, 1)
			} else {
				gauge(desc, 0)
			}
		}

		boolGauge(c.up, check.StateIsUp && !check.IsPaused)
		boolGauge(c.paused, check.IsPaused)
		boolGauge(c.underMaintenance, check.IsUnderMaintenance)

		if check.CachedResponseTime > 0 {
			gauge(c.responseTime, check.CachedResponseTime)
		}

		boolGauge(c.sslIsMonitored, check.SSLConfig != nil)
	}

	return nil
}

// listAllChecks pages through the uptime.com API until all checks are retrieved.
func (c *Collector) listAllChecks(ctx context.Context) ([]upapi.Check, error) {
	var all []upapi.Check
	page := int64(1)

	for {
		result, err := c.api.Checks().List(ctx, upapi.CheckListOptions{
			Page:     page,
			PageSize: pageSize,
		})
		if err != nil {
			return nil, fmt.Errorf("listing checks page %d: %w", page, err)
		}

		all = append(all, result.Items...)

		if int64(len(all)) >= result.TotalCount {
			break
		}
		page++
	}

	return all, nil
}
