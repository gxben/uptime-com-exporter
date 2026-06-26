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

package main

import (
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/uptime-com/uptime-client-go/v2/pkg/upapi"

	"github.com/gxben/uptime-com-exporter/internal/collector"
)

var version = "dev" // injected by ldflags at build time

func main() {
	var (
		listenAddr    = flag.String("web.listen-address", ":9400", "Address on which to expose metrics")
		metricsPath   = flag.String("web.telemetry-path", "/metrics", "Path under which to expose metrics")
		apiKey        = flag.String("uptime.api-key", "", "uptime.com API key (or set UPTIME_API_KEY env var)")
		scrapeTimeout = flag.Duration("uptime.scrape-timeout", 30*time.Second, "Timeout for a single uptime.com API scrape")
		showVersion   = flag.Bool("version", false, "Print version and exit")
	)
	flag.Parse()

	if *showVersion {
		fmt.Printf("uptime-com-exporter %s\n", version)
		os.Exit(0)
	}

	// API key: flag takes precedence over env var.
	key := *apiKey
	if key == "" {
		key = os.Getenv("UPTIME_API_KEY")
	}
	if key == "" {
		slog.Error("uptime API key is required (--uptime.api-key or UPTIME_API_KEY)")
		os.Exit(1)
	}

	api, err := upapi.New(
		upapi.WithToken(key),
		upapi.WithRetry(3, 10*time.Second, os.Stderr),
	)
	if err != nil {
		slog.Error("failed to create uptime.com API client", "err", err)
		os.Exit(1)
	}

	coll := collector.New(api, *scrapeTimeout)

	reg := prometheus.NewRegistry()
	reg.MustRegister(coll)

	mux := http.NewServeMux()
	mux.Handle(*metricsPath, promhttp.HandlerFor(reg, promhttp.HandlerOpts{
		EnableOpenMetrics: true,
	}))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		_, _ = fmt.Fprintf(w, `<html>
<head><title>uptime.com Exporter</title></head>
<body>
<h1>uptime.com Exporter</h1>
<p>Version: %s</p>
<p><a href="%s">Metrics</a></p>
</body>
</html>`, version, *metricsPath)
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = fmt.Fprintln(w, "ok")
	})

	slog.Info("starting uptime-com-exporter",
		"version", version,
		"listen", *listenAddr,
		"metrics_path", *metricsPath,
	)

	server := &http.Server{
		Addr:         *listenAddr,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: *scrapeTimeout + 10*time.Second,
		IdleTimeout:  120 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil {
		slog.Error("server exited", "err", err)
		os.Exit(1)
	}
}
