# Telemetry pipeline — design and operating doctrine

> Bottom line: every service emits OTLP to a single in-cluster OpenTelemetry
> Collector gateway. The Collector enriches, samples, and fans out to Tempo
> (traces), Prometheus (metrics, scraped), and Loki (logs). One ingress point,
> one identity contract, one place to change behavior.

## 1. Architecture

```
┌──────────────────────┐  OTLP gRPC :4317  ┌────────────────────────┐
│ Application Pods     │ ─────────────────▶│ otel-collector         │
│  (default ns)        │  OTLP HTTP :4318  │ (observability ns)     │
└──────────────────────┘                   ├────────────────────────┤
                                           │ receivers: otlp        │
                                           │ processors:            │
                                           │   memory_limiter       │
                                           │   k8sattributes        │
                                           │   resource             │
                                           │   tail_sampling        │
                                           │   batch                │
                                           │ exporters:             │
                                           │   otlp/tempo  (traces) │
                                           │   prometheus  (metrics)│
                                           │   otlphttp/loki (logs) │
                                           └─────┬────────┬─────────┘
                                                 │        │
                                ┌────────────────┘        └────────────────┐
                                ▼                                          ▼
                       ┌─────────────────┐                       ┌─────────────────┐
                       │ Tempo (traces)  │                       │ Loki (logs)     │
                       └─────────────────┘                       └─────────────────┘

Prometheus scrapes the Collector's prometheus exporter on :8889 (and Collector
self metrics on :8888) — exemplars carry trace_id back into Grafana.
```

Source manifest: [`observability/k8s/base/40-otel-collector.yaml`](../k8s/base/40-otel-collector.yaml).

## 2. Receivers

| Receiver        | Endpoint           | Notes                              |
| --------------- | ------------------ | ---------------------------------- |
| `otlp/grpc`     | `:4317`            | Primary protocol; lowest overhead  |
| `otlp/http`     | `:4318`            | For runtimes lacking gRPC          |
| `prometheus/self` | `:8888`          | Collector internals                |

## 3. Processors (order matters)

1. `memory_limiter` — back-pressures upstream when RSS hits 80%, spike margin 25%.
2. `k8sattributes` — enriches with `k8s.namespace.name`, `k8s.pod.name`, `k8s.deployment.name`, `k8s.node.name`, `k8s.pod.uid`.
3. `resource` — stamps `cluster=onprem-k3s`, `deployment.environment=dev` (overlay-tunable).
4. `tail_sampling` (traces only) — see §4.
5. `batch` — 5s flush, batches ≤ 2048 items.

## 4. Sampling strategy

Tail-based to balance signal vs. cost:

| Policy            | Rule                                        | Effect                    |
| ----------------- | ------------------------------------------- | ------------------------- |
| `errors`          | Span status = `ERROR`                       | Always retain             |
| `slow`            | Trace latency > 750 ms                      | Always retain             |
| `sample-10pct`    | Probabilistic 10%                            | Healthy traffic baseline  |

> Rationale: keep 100% of incidents and tail-latency outliers; sample the
> happy path for trend visibility. `decision_wait=10s` tolerates cross-service
> trace assembly latency.

Tuning knob: change `sampling_percentage` in
`observability/k8s/base/40-otel-collector.yaml` ConfigMap, or override via
overlay patch.

## 5. Exporters

- **Traces → Tempo** via `otlp/tempo` (gRPC `tempo.observability.svc:4317`, TLS off in-cluster).
- **Metrics → Prometheus** via the `prometheus` exporter on `:8889`. Prometheus scrapes the Collector. Exemplars enabled (trace_id correlation).
- **Logs → Loki** via `otlphttp/loki` to `http://loki.observability.svc:3100/otlp` (Loki 3.x native OTLP ingest, structured-metadata aware).

## 6. Per-service integration

Apply via Kustomize component
[`kustomize/components/observability-app-stack`](../../kustomize/components/observability-app-stack/).
It standardizes on these env vars across every service:

| Variable                      | Value                                                                |
| ----------------------------- | -------------------------------------------------------------------- |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector.observability.svc.cluster.local:4317`         |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc`                                                               |
| `OTEL_SERVICE_NAME`           | `<service>` (e.g. `frontend`, `checkoutservice`)                      |
| `OTEL_RESOURCE_ATTRIBUTES`    | `service.namespace=default,deployment.environment=dev`               |
| `ENABLE_TRACING`              | `1` (legacy flag in Go services)                                     |

The frontend additionally carries `prometheus.io/scrape` annotations so its
native `/metrics` endpoint is also scraped — useful when validating SDK
metrics directly without going through the Collector.

## 7. Identity & correlation contract

Every signal **must** carry these labels for Grafana drilldowns to work:

- `service.name` (OTel) → renamed to `service_name` in Prom/Loki for parity.
- `k8s.namespace.name` → `namespace`.
- `k8s.pod.name` → `pod`.
- `cluster`, `deployment.environment`.
- `trace_id` in log lines (best-effort JSON extraction in Promtail; native via OTLP-logs).

W3C `traceparent` propagation is required across HTTP and gRPC. The Boutique
services already comply via OTel SDK auto-instrumentation.

## 8. Cardinality guardrails

Banned label sources (do not emit):

- Raw user IDs, session IDs, request IDs as **metric** labels — keep them in logs/spans.
- Raw URLs with path parameters — use `http.route` template.
- Per-pod hashes — use `deployment.name` instead.

Loki label limits enforced at the server (see
[`observability/k8s/base/20-loki.yaml`](../k8s/base/20-loki.yaml)):

- `max_global_streams_per_user: 5000` (dev), 10000 (prod-like).
- `max_label_names_per_series: 30`.

## 9. Failure modes & mitigation

| Failure                            | Symptom                          | Mitigation                                                  |
| ---------------------------------- | -------------------------------- | ----------------------------------------------------------- |
| Collector OOM                      | Pods restart, gaps in dashboards | `memory_limiter` already configured; raise pod memory limit |
| Tempo backend unavailable          | Traces missing, logs/metrics OK  | Collector buffers via `batch`; restart Tempo                |
| Loki ingest 429                    | Log lines dropped                | Lower app log volume or raise `ingestion_rate_mb`           |
| Cluster DNS broken                 | OTLP exports fail cluster-wide   | Run [`ops/fix-dns-failure/dns-heal.sh`](../../ops/fix-dns-failure/) |

## 10. Validation

A successful validation looks like:

1. `kubectl -n observability port-forward svc/otel-collector 8888:8888` →
   `curl http://localhost:8888/metrics | grep otelcol_receiver_accepted_spans` → counter increasing.
2. Trace one user request:
   - Grafana → Explore → **Tempo** → query by `service.name="frontend"` → see multi-service trace.
   - Grafana → Explore → **Loki** → query `{namespace="default", app="frontend"}` → click trace ID → drilldown to Tempo.
3. Hit `up{job="otel-collector"} == 1` in Prometheus.
