# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make build        # compile to bin/uptime-com-exporter (CGO_ENABLED=0, trimpath, version via ldflags)
make run          # build then run (reads UPTIME_API_KEY from env)
make test         # go test ./... -race -count=1 -coverprofile=coverage.out
make fmt          # go fmt
make vet          # go vet
make fix          # go fix
make lint         # golangci-lint (auto-installed into bin/)
make sec          # gosec security scan (auto-installed into bin/)
make vuln         # govulncheck CVE scan (auto-installed into bin/)
make all          # fmt → vet → fix → lint → build (sec/vuln must be called explicitly)
make docker       # multi-arch image build (linux/amd64, linux/arm64), no push
make docker-push  # build + push to ghcr.io/gxben/uptime-com-exporter
make helm-package # package the Helm chart as a .tgz
make clean        # remove bin/, coverage.out, *.tgz
```

Tools (`golangci-lint`, `govulncheck`, `gosec`) are installed on demand into `bin/` via `test -x` guards — no global installs needed.

Run a single test package:
```bash
go test ./internal/collector/... -run TestFoo -v
```

The binary accepts `--uptime.api-key` or `UPTIME_API_KEY` (env takes lower precedence than flag). Other flags: `--web.listen-address` (default `:9400`), `--web.telemetry-path` (default `/metrics`), `--uptime.scrape-timeout` (default `30s`).

## Architecture

This is a single-binary Prometheus exporter. The data flow is:

```
Prometheus scrape → collector.Collect() → upapi.Checks().List() → uptime.com API
```

**`main.go`** — wires everything: parses flags, constructs `upapi.API` via the official SDK (`github.com/uptime-com/uptime-client-go/v2`), instantiates the collector, registers it on a fresh (non-default) `prometheus.Registry`, and serves three routes: `/metrics`, `/` (landing page), `/healthz`.

**`internal/collector/collector.go`** — the only domain logic. Implements `prometheus.Collector`. `Collect()` calls the private `collect()` and always emits `uptime_scrape_duration_seconds` and `uptime_scrape_success` regardless of API errors. `listAllChecks()` handles SDK pagination (`Page`/`PageSize`; stops when `len(all) >= result.TotalCount`).

### Metrics emitted

All check metrics carry labels: `pk`, `name`, `address`, `check_type`, `tags` (comma-joined).

| Metric | Source |
|---|---|
| `uptime_check_up` | `StateIsUp && !IsPaused` |
| `uptime_check_paused` | `IsPaused` |
| `uptime_check_under_maintenance` | `IsUnderMaintenance` |
| `uptime_check_response_time_ms` | `CachedResponseTime` (omitted when 0) |
| `uptime_check_ssl_monitored` | `SSLConfig != nil` |
| `uptime_scrape_duration_seconds` | wall time of full API fetch |
| `uptime_scrape_success` | 1 on success, 0 on any error |

### SDK notes

The uptime.com SDK (`upapi.API`) is constructed with `upapi.WithToken()` (not `WithBearerToken`) and `upapi.WithRetry()` for automatic 429 handling. `upapi.Check` fields relevant to this exporter: `PK int64`, `Name`, `Address`, `CheckType`, `Tags []string`, `StateIsUp`, `IsPaused`, `IsUnderMaintenance`, `CachedResponseTime float64`, `SSLConfig *CheckSSLCertConfig`. SSL certificate validity/expiry days are **not** available as a field — `SSLConfig` is configuration only; `StateIsUp` is the validity signal for SSL-type checks.

## CI/CD & Release

Four workflows; all support `workflow_dispatch` for manual runs:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | push/PR to `main` | test → lint → build → docker (push on `main`, build-only on PRs) |
| `sec.yml` | push/PR to `main` | gosec security scan |
| `vuln.yml` | push/PR to `main` | govulncheck CVE scan |
| `release.yml` | `workflow_dispatch` only | semantic-release → versioned Docker image → Helm chart OCI push |

**Release flow** (`release.yml`):
1. `semantic-release` reads conventional commits since the last tag, bumps the version, writes `CHANGELOG.md`, pushes it back to `main`, and creates a GitHub Release.
2. If a new version was published, `docker` job checks out the new tag and pushes a versioned multi-arch image to GHCR.
3. `helm` job packages and pushes the chart to `oci://ghcr.io/gxben/charts`.

**Secret requirement**: set `RELEASE_TOKEN` in repository secrets to a PAT (or GitHub App token) with `contents: write` so semantic-release can push the CHANGELOG commit back to `main` when branch protection is enabled. Falls back to `GITHUB_TOKEN` if the secret is absent.

**Conventional commits** (enforced by pre-commit hook):
- `feat:` → minor version bump
- `fix:`, `perf:`, `refactor:`, `revert:` → patch bump
- `BREAKING CHANGE:` footer or `!` suffix → major bump
- `docs:`, `chore:`, `style:`, `test:`, `ci:` → no release

The Docker image is `distroless/static-debian12:nonroot`. `VERSION` is injected via `-X main.version` at build time; without a git tag it falls back to `dev`.

## Helm Chart

`charts/uptime-com-exporter/` is a standard Helm chart. Key opt-in features (all `false` by default):
- `serviceMonitor.enabled` — Prometheus Operator `ServiceMonitor`
- `prometheusRule.enabled` — ships three default alert rules (`UptimeCheckDown`, `UptimeExporterDown`, `UptimeSSLExpiringSoon`)
- `ingress.enabled`, `autoscaling.enabled`

The API key is stored in a `Secret` created by the chart (`uptime.apiKey`) or referenced from an existing one (`uptime.existingSecret` + `uptime.existingSecretKey`). The Deployment's `checksum/secret` annotation forces pod restarts on Secret changes.

## License

Apache 2.0. All `.go` files must carry the standard header (see any existing file). Copyright holder: `Benjamin Zores`.
