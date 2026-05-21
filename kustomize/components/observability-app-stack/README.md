# Observability — App Stack Component

Wires every Online Boutique microservice to the in-cluster observability stack
(see [`observability/k8s/`](../../../observability/k8s/)).

## What it does

For each microservice Deployment, it sets:

- `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4317`
- `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`
- `OTEL_SERVICE_NAME=<service>`
- `OTEL_RESOURCE_ATTRIBUTES=service.namespace=default,deployment.environment=dev`
- `ENABLE_TRACING=1` (legacy flag honored by Go services)
- `prometheus.io/scrape: "true"` annotations on services that expose native `/metrics` (frontend)

Telemetry flow:

```
app -> otel-collector (cluster, observability ns)
        -> tempo  (traces)
        -> prometheus (metrics, via /metrics on :8889)
        -> loki   (logs via OTLP HTTP)
```

## How to use

In an environment overlay, replace `observability-onprem` with this component:

```yaml
# kustomize/environments/onprem/base/kustomization.yaml
components:
  - ../../../components/observability-app-stack
```

Then deploy the platform stack first, the app overlay second:

```bash
kubectl apply -k observability/k8s/overlays/dev
kubectl apply -k kustomize/environments/onprem/k3s
```

## Notes

- Cartservice (.NET) and Adservice (Java) honor the standard `OTEL_*` env vars from
  their auto-instrumentation SDKs.
- Loadgenerator (Locust + Python) is instrumented via OTel SDK env vars.
- Prometheus discovers any pod opted in via `prometheus.io/scrape: "true"` —
  most app metrics still flow through the OTel Collector's Prometheus exporter
  (`otel-collector.observability.svc:8889`).
