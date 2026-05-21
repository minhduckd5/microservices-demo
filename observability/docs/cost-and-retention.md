# Cost, retention, and cardinality controls

> Bottom line: dev runs ~10–15 GiB total observability storage and a single replica
> of every component; prod-like keeps 30 days of metrics/logs at ~210 GiB total
> with no HA dependencies on managed infra. Escalation paths to remote-write /
> object storage are documented here so the team upgrades on policy, not panic.

## 1. Per-environment retention matrix

| Component   | Dev retention | Dev storage | Prod-like retention | Prod-like storage |
| ----------- | ------------- | ----------- | ------------------- | ----------------- |
| Prometheus  | 7d / 7 GiB    | PVC 10 GiB  | 30d / 50 GiB        | PVC 60 GiB        |
| Loki        | 7d            | PVC 10 GiB  | 30d                 | PVC 100 GiB       |
| Tempo       | 72h           | PVC 10 GiB  | 72h                 | PVC 50 GiB        |
| Alertmanager| n/a (state)   | PVC 2 GiB   | n/a (state)         | PVC 2 GiB         |
| Grafana     | n/a (state)   | PVC 5 GiB   | n/a (state)         | PVC 5 GiB         |
| **Total**   | —             | **~37 GiB** | —                   | **~217 GiB**      |

Patches that enforce these are in
[`observability/k8s/overlays/dev/kustomization.yaml`](../k8s/overlays/dev/kustomization.yaml)
and
[`observability/k8s/overlays/prod-like/kustomization.yaml`](../k8s/overlays/prod-like/kustomization.yaml).

## 2. Sizing assumptions

| Driver                              | Dev assumption          | Prod-like assumption     |
| ----------------------------------- | ----------------------- | ------------------------ |
| Active series in Prometheus         | ≤ 50k                   | ≤ 250k                   |
| Samples ingested / s                | ≤ 5k                    | ≤ 25k                    |
| Log volume / day                    | ≤ 1 GiB                 | ≤ 20 GiB                 |
| Trace spans / s (post-sampling)     | ≤ 200                   | ≤ 1.5k                   |
| Avg spans / trace                   | 8                       | 12                       |
| Trace sampling                      | 10% baseline + tails    | 5% baseline + tails      |

Storage rule of thumb:

- **Prometheus**: ~1.3 bytes/sample → 7d * 5k samples/s * 1.3 ≈ 4 GiB raw; 2x WAL/headroom = 8 GiB.
- **Loki**: ~0.5 bytes/byte after compression → 7d * 1 GiB ≈ 7 GiB.
- **Tempo**: 200 spans/s * 72h * 200 B ≈ 10 GiB.

Validate with `node_filesystem_avail_bytes{mountpoint=~"/var/lib/.*"}` and the
`Cluster - Node & Pod Health` dashboard.

## 3. Sampling controls

Tail-based sampling is enforced at the Collector
([`40-otel-collector.yaml`](../k8s/base/40-otel-collector.yaml)):

- Errors and slow (>750 ms) traces → **always retained**.
- Healthy baseline → **10% probabilistic**.

To change for prod-like, add a Kustomize patch on the
`otel-collector-config` ConfigMap or fork the manifest under the overlay.

## 4. Cardinality guardrails

### Prometheus

- High-risk labels are dropped at scrape via `metric_relabel_configs`
  (see `otel-collector` job).
- App services must use `http.route` (templated path), never raw URLs.
- Per-pod metrics are aggregated **away from `pod`** for SLO dashboards;
  per-pod views remain in cluster-health dashboards.

### Loki

- Server-side limits in [`20-loki.yaml`](../k8s/base/20-loki.yaml):
  - `max_global_streams_per_user: 5000` (dev) / `10000` (prod-like)
  - `max_label_names_per_series: 30`
  - `max_label_value_length: 4096`
- Promtail strips uncontrolled labels and surfaces only:
  `namespace, pod, container, app, service, level, node`.

### Tempo

- Span attributes carrying PII (emails, addresses, raw payloads) must be
  redacted at the SDK layer or in the Collector via the `attributes` processor
  (not enabled by default — add per-overlay if your domain requires it).

## 5. Escalation paths (when the box is too small)

Activate when sustained ingestion exceeds the assumptions above:

### Prometheus → long-term metrics

- **Cheapest**: enable `--web.enable-remote-write-receiver` (already on) and
  add a remote-write target to **Mimir** or **Thanos sidecar** with object
  storage (S3, MinIO, Azure Blob).
- **Trigger**: `prometheus_tsdb_head_series > 200_000` for >24h, or PVC >70%.

### Loki → object-storage chunks

- Move from `filesystem` backend to **S3-compatible** (MinIO is the cheapest
  on-prem option) by editing the ConfigMap under `storage_config` /
  `common.storage`.
- **Trigger**: log volume >20 GiB/day or PVC >70%.

### Tempo → S3-compatible blocks

- Switch `storage.trace.backend: local` → `s3` and supply credentials via
  Secret. Same MinIO bucket as Loki is fine; isolate via prefix.
- **Trigger**: any sustained tracing scale or compliance need for >72h retention.

### Alerting noise → MMBR + ticketing

- Wire Alertmanager to PagerDuty/Slack (placeholders in
  [`11-alertmanager.yaml`](../k8s/base/11-alertmanager.yaml)).
- Adopt SLO multi-window multi-burn-rate alerts (already shipped — see
  `slo-burn-rate` group) and **delete** redundant raw-error alerts to silence
  the `HighHTTP5xxRate` / `FrontendErrorBudgetBurn*` overlap.

## 6. Cost levers (in priority order)

1. **Sampling percentage** (single line in OTel Collector ConfigMap).
2. **Loki retention** (`limits_config.retention_period`).
3. **Prometheus retention** (`--storage.tsdb.retention.time`).
4. **Drop noisy metrics** via `metric_relabel_configs`.
5. **Move to object storage** for Loki/Tempo (eliminates PVC sizing as a constraint).

## 7. Operational SLOs for the platform itself

| Component       | Availability | Validation                                    |
| --------------- | ------------ | --------------------------------------------- |
| Prometheus      | 99.5%        | `up{job="prometheus"}`, scrape duration < 5s  |
| Alertmanager    | 99.9%        | `up{job="alertmanager"}`, paging-grade        |
| OTel Collector  | 99.5%        | `otelcol_processor_dropped_spans_total == 0`  |
| Grafana         | 99%          | Liveness probe                                 |
| Loki            | 99%          | `loki_request_duration_seconds_count{status_code="200"}` |
| Tempo           | 99%          | `tempo_request_duration_seconds_count{status_code="200"}` |

Alerts already cover Prometheus + Alertmanager + DNS dependency. Extend per
business risk appetite.
