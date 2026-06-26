# uptime-com-exporter

A [Prometheus](https://prometheus.io/) exporter for the [uptime.com](https://uptime.com/) monitoring platform. It exposes check status, response times, and maintenance state as Prometheus metrics, ready to be scraped by any Prometheus-compatible system.

Built on the official [uptime-com Go SDK](https://github.com/uptime-com/uptime-client-go).

---

## Metrics

All check metrics share the same label set: `pk`, `name`, `address`, `check_type`, `tags`.

| Metric | Type | Description |
|---|---|---|
| `uptime_check_up` | Gauge | `1` if the check is currently passing (up and not paused) |
| `uptime_check_paused` | Gauge | `1` if the check is paused |
| `uptime_check_under_maintenance` | Gauge | `1` if the check is in a maintenance window |
| `uptime_check_response_time_ms` | Gauge | Most recent cached response time (ms); absent when 0 |
| `uptime_check_ssl_monitored` | Gauge | `1` if the check has an SSL certificate monitoring config |
| `uptime_scrape_duration_seconds` | Gauge | Wall time spent fetching data from the uptime.com API |
| `uptime_scrape_success` | Gauge | `1` if the last scrape completed without errors |

---

## Requirements

- An [uptime.com API key](https://uptime.com/api/v1/documentation/) (read-only access is sufficient)
- Go 1.26+ (to build from source)

---

## Usage

### Binary

```bash
# API key via flag
uptime-com-exporter --uptime.api-key=<YOUR_KEY>

# API key via environment variable (recommended)
export UPTIME_API_KEY=<YOUR_KEY>
uptime-com-exporter
```

All flags:

| Flag | Default | Description |
|---|---|---|
| `--uptime.api-key` | — | uptime.com API key (`UPTIME_API_KEY` env var as fallback) |
| `--uptime.scrape-timeout` | `30s` | Timeout for a full API scrape |
| `--web.listen-address` | `:9400` | Address to expose metrics on |
| `--web.telemetry-path` | `/metrics` | Path to expose metrics at |
| `--version` | — | Print version and exit |

Endpoints exposed:

| Path | Description |
|---|---|
| `/metrics` | Prometheus metrics (OpenMetrics format) |
| `/healthz` | Liveness probe — returns `200 ok` |
| `/` | Landing page with link to `/metrics` |

### Docker

```bash
docker run --rm \
  -e UPTIME_API_KEY=<YOUR_KEY> \
  -p 9400:9400 \
  ghcr.io/gxben/uptime-com-exporter:latest
```

### Helm (Kubernetes)

The chart is published to GHCR as an OCI artifact.

```bash
# Install with a chart-managed Secret
helm install uptime-com-exporter \
  oci://ghcr.io/gxben/charts/uptime-com-exporter \
  --set uptime.apiKey=<YOUR_KEY>

# Install using an existing Secret (e.g. managed by External Secrets Operator)
helm install uptime-com-exporter \
  oci://ghcr.io/gxben/charts/uptime-com-exporter \
  --set uptime.existingSecret=my-secret \
  --set uptime.existingSecretKey=api-key
```

Enable Prometheus Operator integration:

```bash
helm install uptime-com-exporter \
  oci://ghcr.io/gxben/charts/uptime-com-exporter \
  --set uptime.apiKey=<YOUR_KEY> \
  --set serviceMonitor.enabled=true \
  --set prometheusRule.enabled=true
```

The chart ships three default alert rules when `prometheusRule.enabled=true`:

| Alert | Severity | Condition |
|---|---|---|
| `UptimeCheckDown` | critical | `uptime_check_up == 0` for 5 min |
| `UptimeExporterDown` | warning | `uptime_scrape_success == 0` for 5 min |
| `UptimeSSLExpiringSoon` | warning | `uptime_check_ssl_days_remaining < 14` for 1 h |

Key chart values:

| Value | Default | Description |
|---|---|---|
| `uptime.apiKey` | `""` | API key (stored in a chart-managed Secret) |
| `uptime.existingSecret` | `""` | Use a pre-existing Secret instead |
| `uptime.scrapeTimeout` | `"30s"` | Scrape timeout passed to the exporter |
| `serviceMonitor.enabled` | `false` | Create a Prometheus Operator `ServiceMonitor` |
| `prometheusRule.enabled` | `false` | Create a Prometheus Operator `PrometheusRule` |
| `serviceMonitor.interval` | `"60s"` | Prometheus scrape interval |

---

## Development

### Pre-commit hooks

Install [pre-commit](https://pre-commit.com/) then activate the hooks:

```bash
pip install pre-commit
pre-commit install --hook-type pre-commit --hook-type commit-msg
```

Hooks enforce:
- **Conventional Commits** format on every commit message
- No merge conflict markers, trailing whitespace, or missing newlines
- `go build`, `go mod tidy`, `go test`, `go fmt`, `golangci-lint`, `gosec`, and `govulncheck` on every push

### Commit convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/). The format is:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Common types and their effect on versioning:

| Type | Release |
|---|---|
| `feat` | minor |
| `fix`, `perf`, `refactor`, `revert` | patch |
| `BREAKING CHANGE` footer or `!` suffix | major |
| `docs`, `chore`, `style`, `test`, `ci` | none |

### Make targets

Tools (`golangci-lint`, `govulncheck`, `gosec`) are installed on demand into `bin/` — no global installation required.

```bash
make help         # list all targets

make mod          # download & tidy modules
make build        # compile to bin/uptime-com-exporter
make run          # build and run (reads UPTIME_API_KEY from env)
make test         # run tests with race detector

make fmt          # gofmt
make vet          # go vet
make lint         # golangci-lint
make sec          # gosec security scan
make vuln         # govulncheck CVE scan
make all          # fmt → vet → fix → lint → build  (sec/vuln must be called explicitly)

make docker       # build multi-arch image locally (no push)
make docker-push  # build and push to GHCR
make helm-package # package the Helm chart as a .tgz

make clean        # remove bin/, coverage.out, *.tgz
```

Run a single test:

```bash
go test ./internal/collector/... -run TestFoo -v
```

### CI/CD

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` | push / PR to `main` | Tests, lint, build, Docker image (push on `main` only) |
| `sec.yml` | push / PR to `main` | gosec security scan |
| `vuln.yml` | push / PR to `main` | govulncheck CVE scan |
| `release.yml` | manual `workflow_dispatch` | semantic-release → versioned Docker image → Helm chart |

Releases are fully automated via [semantic-release](https://semantic-release.gitbook.io): trigger the `release.yml` workflow manually, and it will determine the next version from conventional commits, update `CHANGELOG.md`, create a GitHub Release, and publish the Docker image and Helm chart.

> **Note**: set `RELEASE_TOKEN` in repository secrets (PAT with `contents: write`) so semantic-release can push the CHANGELOG commit back to `main` when branch protection is enabled.

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).
Copyright 2026 Benjamin Zores.
