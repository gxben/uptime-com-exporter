# Copyright 2026 Benjamin Zores
# Apache License, Version 2.0 (see LICENSE or https://www.apache.org/licenses/LICENSE-2.0.txt)
# SPDX-License-Identifier: Apache-2.0

PKG_NAME = github.com/gxben/uptime-com-exporter
VERSION  = $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
IMAGE    = ghcr.io/gxben/uptime-com-exporter

export GO111MODULE = on
BINDIR = bin

GOLINT       = $(BINDIR)/golangci-lint
GOVULNCHECK  = $(BINDIR)/govulncheck
GOSEC        = $(BINDIR)/gosec

PKGS = $(shell go list ./...)

V = 0
Q = $(if $(filter 1,$V),,@)
M = $(shell printf "\033[34;1m▶\033[0m")

.PHONY: all
all: mod fmt vet fix lint build ; @ ## Run all checks then build
	$Q echo "done"

# ── Dependencies ──────────────────────────────────────────────────────────────

.PHONY: mod
mod: ; $(info $(M) collecting modules…) @ ## Download and tidy Go modules
	$Q go mod download
	$Q go mod tidy

.PHONY: update
update: ; $(info $(M) updating modules…) @ ## Update all Go dependencies
	$Q go get -u ./...
	$Q go mod tidy

# ── Build ─────────────────────────────────────────────────────────────────────

.PHONY: build
build: ; $(info $(M) building executable…) @ ## Build the exporter binary
	$Q mkdir -p $(BINDIR)
	$Q CGO_ENABLED=0 go build \
		-ldflags="-s -w -X main.version=$(VERSION)" \
		-trimpath \
		-o $(BINDIR)/uptime-com-exporter \
		.

.PHONY: run
run: build ; $(info $(M) running exporter…) @ ## Build and run locally (requires UPTIME_API_KEY)
	$Q UPTIME_API_KEY=$${UPTIME_API_KEY} $(BINDIR)/uptime-com-exporter

# ── Code quality ──────────────────────────────────────────────────────────────

.PHONY: fmt
fmt: ; $(info $(M) running go fmt…) @ ## Format all source files
	$Q go fmt $(PKGS)

.PHONY: vet
vet: ; $(info $(M) running go vet…) @ ## Run static analysis
	$Q go vet $(PKGS) ; exit 0

.PHONY: fix
fix: ; $(info $(M) running go fix…) @ ## Apply go fix to all packages
	$Q go fix $(PKGS)

.PHONY: get-lint
get-lint: ; $(info $(M) downloading golangci-lint…) @
	$Q test -x $(GOLINT) || GOBIN="$(PWD)/$(BINDIR)/" go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest

.PHONY: lint
lint: get-lint ; $(info $(M) running golangci-lint…) @ ## Run linter
	$Q $(GOLINT) run ./... ; exit 0

.PHONY: get-govulncheck
get-govulncheck: ; $(info $(M) downloading govulncheck…) @
	$Q test -x $(GOVULNCHECK) || GOBIN="$(PWD)/$(BINDIR)/" go install golang.org/x/vuln/cmd/govulncheck@latest

.PHONY: vuln
vuln: get-govulncheck ; $(info $(M) running govulncheck…) @ ## Check for known CVEs in dependencies
	$Q $(GOVULNCHECK) ./... ; exit 0

.PHONY: get-gosec
get-gosec: ; $(info $(M) downloading gosec…) @
	$Q test -x $(GOSEC) || GOBIN="$(PWD)/$(BINDIR)/" go install github.com/securego/gosec/v2/cmd/gosec@latest

.PHONY: sec
sec: get-gosec ; $(info $(M) running gosec…) @ ## Run security-oriented AST/SSA checks
	$Q $(GOSEC) -terse ./... ; exit 0

# ── Tests ─────────────────────────────────────────────────────────────────────

.PHONY: test
test: ; $(info $(M) running test suite…) @ ## Run tests with race detector and coverage
	$Q go test ./... -race -count=1 -coverprofile=coverage.out

# ── Docker ────────────────────────────────────────────────────────────────────

.PHONY: docker
docker: ; $(info $(M) building docker image…) @ ## Build multi-arch Docker image (no push)
	$Q docker buildx build \
		--build-arg VERSION=$(VERSION) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(VERSION) \
		-t $(IMAGE):latest \
		.

.PHONY: docker-push
docker-push: ; $(info $(M) building and pushing docker image…) @ ## Build and push multi-arch Docker image to GHCR
	$Q docker buildx build \
		--build-arg VERSION=$(VERSION) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(VERSION) \
		-t $(IMAGE):latest \
		--push \
		.

# ── Helm ──────────────────────────────────────────────────────────────────────

.PHONY: helm-package
helm-package: ; $(info $(M) packaging helm chart…) @ ## Package the Helm chart
	$Q helm package charts/uptime-com-exporter \
		--version $(shell echo $(VERSION) | sed 's/^v//') \
		--app-version $(VERSION)

# ── Housekeeping ──────────────────────────────────────────────────────────────

.PHONY: clean
clean: ; $(info $(M) cleaning…) @ ## Remove generated artefacts
	$Q rm -rf $(BINDIR)/* coverage.out *.tgz

.PHONY: help
help: ## Display this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
