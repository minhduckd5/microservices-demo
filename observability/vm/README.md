# VM-mode observability stack

Drop-in parity stack for teams running the demo on Vagrant VMs without
Kubernetes. All components match the K8s package under
[`observability/k8s/`](../k8s/) on **major version, configuration intent,
correlation contract, and dashboards**, so dashboards/runbooks transfer
unchanged when migrating between modes.

## Topology

Default deploy target: **registry-vm** (192.168.1.220 for local Vagrant, or **192.168.31.220** for Proxmox VE). It already has Docker installed by `playbooks/registry-vm.yml`, is reachable from the K3s nodes, and does not run app workloads. Override with `--extra-vars 'obs_target=<inventory_group>'`.

> [!TIP]
> **Custom Subnets (Proxmox / LAN):** If your LAN or PVE range is different (e.g. `192.168.31.x`), ensure you replace `192.168.1.x` with your actual IPs in `config/prometheus/prometheus.yml` under static targets so Prometheus can scrape the node exporters successfully!

```
[Apps on K3s nodes / Compose VMs]
          │ OTLP gRPC :4317
          ▼
[OTel Collector] ──► Prometheus :9090
                ├──► Loki        :3100
                └──► Tempo       :3200
                          │
                          ▼
                     [Grafana :3000]
```

## Quick start

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/observability-vm.yml
```

Default endpoints:

| Component    | URL                              |
| ------------ | -------------------------------- |
| Grafana      | http://192.168.1.220:3000        |
| Prometheus   | http://192.168.1.220:9090        |
| Alertmanager | http://192.168.1.220:9093        |
| Loki         | http://192.168.1.220:3100        |
| Tempo        | http://192.168.1.220:3200        |
| OTLP         | 192.168.1.220:4317 (gRPC) / :4318 (HTTP) |

Initial credentials: `admin / admin`. Rotate immediately for non-demo use
(edit the `GF_SECURITY_ADMIN_PASSWORD` env in
[`docker-compose.yml`](./docker-compose.yml)).

## Wiring app workloads

Set on every microservice (whether running in K3s or directly on the VMs):

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://<registry-vm-ip>:4317   # e.g., 192.168.31.220 for Proxmox VE
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_RESOURCE_ATTRIBUTES=service.name=<svc>,service.namespace=default,environment=dev,cluster=onprem-vm
ENABLE_TRACING=1
```

The K8s package already injects these via the
[`observability-app-stack` Kustomize component](../../kustomize/components/observability-app-stack/).
For VM-mode deployments, set them in your unit/compose files.

## What it does NOT do

- HA: single replicas of every component. For HA, deploy multiple registry-class
  VMs with a load balancer in front of OTLP and a replicated object store
  backend (MinIO) for Loki/Tempo.
- Object storage: Loki and Tempo use local filesystem volumes. Escalate per
  [`../docs/cost-and-retention.md`](../docs/cost-and-retention.md).

## Parity table with K8s package

| Concern                          | K8s package                            | VM package                                |
| -------------------------------- | -------------------------------------- | ----------------------------------------- |
| Prometheus retention (default)   | 7d / 7GB (dev) → 30d / 50GB (prod)      | 15d / 15GB                                |
| Loki retention                   | 168h (dev) → 720h (prod)               | 168h                                      |
| Tempo retention                  | 72h                                    | 72h                                       |
| OTel pipeline                    | tail-sampling + spanmetrics            | tail-sampling + spanmetrics               |
| Grafana datasources              | prom/loki/tempo with derived fields    | identical                                 |
| Dashboards                       | 4 (golden, cluster, logs, traces)      | 1 starter (extend by copying ConfigMap)   |
| Alert rules                      | golden + DNS + SLO burn-rate           | golden + blackbox                         |

## Accessing Logs & Exporting Data

### Viewing Logs (Loki in Grafana)
Loki acts as the log storage engine, but Grafana is your query interface:
1. Open Grafana (`http://<registry-vm-ip>:3000`).
2. Go to the **Explore** tab (compass icon on the left sidebar).
3. Select **Loki** from the datasource dropdown.
4. Query logs using LogQL (e.g. `{service="frontend"}`).

### Data Persistence (Verification)
All metrics, logs, and traces are persisted to Docker named volumes on the `registry-vm` disk:
* Metrics: `observability_prom_data`
* Logs: `observability_loki_data`
* Traces: `observability_tempo_data`

To verify database size and storage growth on-disk, SSH into `registry-vm` and run:
```bash
sudo du -sh /var/lib/docker/volumes/observability_prom_data/_data
sudo du -sh /var/lib/docker/volumes/observability_loki_data/_data
```

### Exporting Data for Analysis & Research (e.g. Thesis)
If you need to analyze raw telemetry data (e.g. for anomaly detection or research):
* **Grafana Export**: In the **Explore** tab, run a query, click **Query Inspector** -> **Data** -> **Download CSV**.
* **REST APIs**: Query the databases directly using Python/R via HTTP GET requests:
  * Prometheus: `http://<registry-vm-ip>:9090/api/v1/query_range?query=<metric>`
  * Loki: `http://<registry-vm-ip>:3100/loki/api/v1/query_range?query=<logql>`
