FROM golang:1.26-alpine AS builder

ARG VERSION=dev
ARG TARGETOS=linux
ARG TARGETARCH=amd64

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build \
      -ldflags="-s -w -X main.version=${VERSION}" \
      -trimpath \
      -o /bin/uptime-com-exporter \
      .

# ─────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

LABEL org.opencontainers.image.title="uptime-com-exporter" \
      org.opencontainers.image.description="Prometheus exporter for uptime.com" \
      org.opencontainers.image.url="https://github.com/gxben/uptime-com-exporter" \
      org.opencontainers.image.source="https://github.com/gxben/uptime-com-exporter"

COPY --from=builder /bin/uptime-com-exporter /uptime-com-exporter

EXPOSE 9400
USER nonroot:nonroot

ENTRYPOINT ["/uptime-com-exporter"]
