# On-Prem Deployment Checklist

Use this checklist to verify your on-prem deployment is fully operational.

## Pre-Deployment

- [x] Vagrant installed: `vagrant --version`
- [x] VMware Desktop OR VirtualBox installed
- [x] Vagrant VMware plugin installed (if using VMware): `vagrant plugin list | grep vmware`
- [x] Ansible installed: `ansible --version`
- [ ] kubectl installed: `kubectl version --client`
- [x] Docker installed: `docker --version`
- [ ] Kind installed (for Docker path): `kind --version`
- [x] Sufficient system resources: 12+ GB RAM, 50+ GB disk
- [x] Repository cloned: `git clone https://github.com/GoogleCloudPlatform/microservices-demo.git`

## Path 1: Vagrant + K3s + Ansible Deployment

### VM Provisioning
- [ ] Run `cd vagrant && vagrant up` (expect 15 minutes first run)
- [ ] Verify VMs: `vagrant status` shows all VMs `running`
- [ ] Test SSH access: `vagrant ssh k3s-control` (should not ask for password)
- [ ] Verify network: `vagrant ssh k3s-control -- ping -c1 192.168.1.220` (registry-vm; IP must match `registry_ip` in inventory)

### Ansible SSH (Vagrant `insert_key = false`)
- [ ] From repo root: `source vagrant/ansible-ssh-env.sh` (or `source vagrant/.ansible-ssh-env.generated`)

### K3s Cluster Bootstrap
- [ ] Run K3s bootstrap playbook: `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/k3s-bootstrap.yml -v`
- [ ] Playbook completes without errors (check final RECAP)
- [ ] Kubeconfig file created: `ls -la k3s-kubeconfig` (file size > 5KB)
- [ ] Set kubeconfig: `export KUBECONFIG=./k3s-kubeconfig`
- [ ] All 3 nodes are Ready: `kubectl get nodes` shows STATUS `Ready` for all 3

### Registry Setup
- [ ] Run registry playbook: `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/registry-vm.yml -v`
- [ ] Registry container running: `vagrant ssh registry-vm -- docker ps | grep registry`
- [ ] Registry responsive: `curl -s http://192.168.1.220:5000/v2/_catalog` (use `registry_ip` from inventory)

### Application Deployment
- [ ] Run app deployment playbook: `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-app.yml -v`
- [ ] Images built and pushed with tag matching inventory (`microservices_image_tag`, default `v0.10.5`) plus `redis:alpine` mirror
- [ ] All pods Running: `kubectl get pods | grep -c Running` (should be ~12+)
- [ ] No pods in ImagePullBackOff: `kubectl get pods | grep -i imagepull` (should be empty)
- [ ] Ingress created: `kubectl get ingress` shows `frontend-ingress`

### Application Access
- [ ] Port-forward works: `kubectl port-forward -n default svc/frontend 8080:80` (same host: `http://localhost:8080`; from another PC use `--address 0.0.0.0` or SSH `-L` — see [QUICKSTART-VAGRANT-ANSIBLE.md](docs/QUICKSTART-VAGRANT-ANSIBLE.md))
- [ ] Browser access: Open `http://localhost:8080` → Online Boutique loads
- [ ] Frontend responsive: Page loads, can browse products
- [ ] Load generator active: Check logs: `kubectl logs -f deploy/loadgenerator`

### Service Verification
- [ ] All services running:
  ```bash
  kubectl get pods -l app | grep -E "frontend|cartservice|productcatalogservice|checkoutservice|currencyservice|emailservice|paymentservice|recommendationservice|shippingservice|adservice|loadgenerator"
  ```
  Should show 1 or more pod for each service.
- [ ] Check logs for errors: `kubectl logs deploy/frontend` (no ERRORs)
- [ ] Services are inter-communicating: Check for successful RPC calls in logs

### Cluster Health
- [ ] Resource usage reasonable: `kubectl top pods` shows < 1000m CPU per pod
- [ ] No pending pods: `kubectl get pods | grep Pending` (empty)
- [ ] No evicted pods: `kubectl get pods | grep Evicted` (empty)
- [ ] Events are clean: `kubectl get events` shows no warnings/errors

## Path 2: Docker-Based (Kind) Deployment

### Prerequisites
- [ ] Docker running: `docker ps` (can list containers)
- [ ] Kind installed: `kind --version`
- [ ] kubectl installed: `kubectl version --client`

### Deployment Execution
- [ ] Run deployment script: `cd scripts && bash deploy-docker-onprem.sh`
- [ ] Script completes with "✓ Online Boutique is ready!" message
- [ ] Registry container running: `docker ps | grep registry`
- [ ] Kind cluster created: `kind get clusters` shows `online-boutique`
- [ ] Kubeconfig available: `ls -la ~/.kube/config-onprem` (file size > 1KB)

### Cluster Verification
- [ ] Set kubeconfig: `export KUBECONFIG=~/.kube/config-onprem`
- [ ] Nodes are Ready: `kubectl get nodes` shows 2 nodes (1 control, 1 worker)
- [ ] All pods Running: `kubectl get pods | grep -c Running` (should be ~12+)
- [ ] Ingress controller ready: `kubectl get deployment -n ingress-nginx`
- [ ] Frontend ingress created: `kubectl get ingress`

### Application Access
- [ ] Port-forward works: `kubectl port-forward svc/frontend 8080:80`
- [ ] Browser access: `http://localhost:8080` → Online Boutique loads
- [ ] Services responsive: Catalog loads, can add items to cart

### Cleanup (if no longer needed)
- [ ] Delete Kind cluster: `kind delete cluster --name=online-boutique`
- [ ] Stop registry: `docker stop local-registry && docker rm local-registry`
- [ ] No hanging containers/networks: `docker ps` and `docker network ls` are clean

## Post-Deployment

### Application Testing
- [ ] Browse frontend dashboard
- [ ] Add product to cart
- [ ] Complete checkout workflow
- [ ] Check all microservices are logging transactions

### Basic Troubleshooting
- [ ] Test inter-pod communication: `kubectl exec <pod> -- curl http://productcatalogservice:3050`
- [ ] Check DNS resolution from pod: `kubectl exec <pod> -- nslookup kubernetes.default`
- [ ] Verify network policies (if enabled): `kubectl get networkpolicies`

### Logs & Observability
- [ ] View pod logs: `kubectl logs <pod-name>`
- [ ] Stream logs: `kubectl logs -f <deployment-name>`
- [ ] Check resource usage: `kubectl top pods` and `kubectl top nodes`
- [ ] Describe problematic pod: `kubectl describe pod <pod>`

## Rollback / Cleanup

### Vagrant + K3s Path
```bash
# Stop but keep VMs:
cd vagrant && vagrant halt

# Destroy everything:
cd vagrant && vagrant destroy -f
```

### Docker Path
```bash
# Delete cluster:
kind delete cluster --name=online-boutique

# Cleanup registry:
docker stop local-registry && docker rm local-registry

# Remove kubeconfig:
rm ~/.kube/config-onprem
```

## Safe suspend / resume runbook (Vagrant + K3s)

<!-- MODIFIED: Add a deterministic suspend/resume procedure to prevent CNI/DNS drift after long VM sleeps. -->

### Why this exists
- `vagrant suspend` can preserve **stale kernel + network + time** state for days.
- On resume, K3s may come up with **broken pod networking (CNI/flannel)**, which looks like “DNS is down” and causes `deploy-app.yml` to hang at rollout waits.

### Pre-suspend (safe)
Run these before `vagrant suspend` if you care about a clean resume.

```bash
# Stop Kubernetes services cleanly (prevents half-restored CNI state)
vagrant ssh k3s-control -c "sudo systemctl stop k3s"
vagrant ssh k3s-worker1 -c "sudo systemctl stop k3s-agent"
vagrant ssh k3s-worker2 -c "sudo systemctl stop k3s-agent"

# Optional: stop registry docker if you’ve seen docker proxy freezes
vagrant ssh registry-vm -c "sudo systemctl stop docker"

# Suspend the VMs
cd vagrant && vagrant suspend
```

### Resume (safe)

```bash
# Resume the VMs
cd vagrant && vagrant up

# Start services (order matters: server first, then agents)
vagrant ssh k3s-control -c "sudo systemctl start k3s"
vagrant ssh k3s-worker1 -c "sudo systemctl start k3s-agent"
vagrant ssh k3s-worker2 -c "sudo systemctl start k3s-agent"

# Registry docker (if stopped)
vagrant ssh registry-vm -c "sudo systemctl start docker"
```

### Post-resume validation (must pass before deploy)

```bash
# 1) Nodes Ready
vagrant ssh k3s-control -c "sudo /usr/local/bin/k3s kubectl get nodes -o wide"

# 2) CoreDNS healthy
vagrant ssh k3s-control -c "sudo /usr/local/bin/k3s kubectl -n kube-system get pods -o wide"

# 3) In-cluster DNS works (this is a symptom check, not the whole story)
bash ops/fix-dns-failure/dns-check.sh

# 4) Pod-to-pod networking sanity (stronger than DNS)
vagrant ssh k3s-control -c "sudo /usr/local/bin/k3s kubectl -n default run net-test --image=busybox:1.36 --restart=Never -- sh -c 'wget -qO- http://kubernetes.default.svc >/dev/null && echo OK || echo FAIL'"
vagrant ssh k3s-control -c "sudo /usr/local/bin/k3s kubectl -n default delete pod net-test --ignore-not-found=true"
```

### Recovery decision tree (fast, deterministic)

- **If DNS fails but pods are reachable**: run `bash ops/fix-dns-failure/dns-heal.sh`.
- **If pod-to-pod connectivity fails or probes time out to `10.42.x.y`** (CNI failure):
  - Attempt one controlled restart:

```bash
vagrant ssh k3s-control -c "sudo systemctl restart k3s"
vagrant ssh k3s-worker1 -c "sudo systemctl restart k3s-agent"
vagrant ssh k3s-worker2 -c "sudo systemctl restart k3s-agent"
```

  - If still broken after ~5 minutes: **rebuild K3s** (lowest time-to-green for labs):
    - run `ansible/playbooks/k3s-bootstrap.yml` again after reinstall, or destroy/recreate VMs.

## Troubleshooting Reference

| Symptom | First Check | Action |
|---------|------------|--------|
| VMs won't start | VMware license | Try: `VAGRANT_DEFAULT_PROVIDER=virtualbox vagrant up` |
| Pods in ImagePullBackOff | Registry reachable? | SSH to node: `ping registry.local` |
| Connection refused to K3s | Kubeconfig correct? | `export KUBECONFIG=./k3s-kubeconfig && kubectl get nodes` |
| Kind cluster missing | Kind installed? | `kind get clusters` and reinstall if needed |
| Port-forward fails | Service exists? | `kubectl get svc frontend` |
| Ansible hangs at "Verify registry is responding" | Registry VM's Docker network stack frozen? | Vagrant suspend cycles can freeze docker proxies. Run `vagrant ssh registry-vm -c "sudo systemctl restart docker"` to flush the daemon network tracking. |
| External port-forward refused | Connection refused from host PC? | Add `--address 0.0.0.0` to `kubectl port-forward` to bind to all interfaces instead of just `127.0.0.1` inside the VM. |
| Ingress not accessible | /etc/hosts updated? | Add `192.168.1.210 boutique.internal` on the **browser PC** (control-plane IP; or `127.0.0.1` for Kind) |
| Pods in CrashLoopBackOff | Liveness/Readiness probes timing out? | Ensure `initialDelaySeconds` (e.g., `20`) and `timeoutSeconds` (e.g., `3`) are configured in the `grpc` probe definitions to survive CPU spikes during cold starts. |
| OpenTelemetry pod crashing | Error parsing `jaeger` exporter? | In newer collector versions (>v0.147.0), the native `jaeger` config is deprecated. Change exporter to `otlp` pointing to `jaeger-all-in-one:4317`. |

## Success Criteria

✅ **Minimum**: Online Boutique loads in browser and user can add items to cart  
✅ **Full**: All 11 microservices running, load generator active, no errors in logs  
✅ **Production-ready**: Network policies active, observability (tracing/metrics) configured

## Next Steps

1. **Deploy variations**: Enable components in `kustomize/kustomization.yaml` (e.g., Istio, observability)
2. **Scale testing**: Add more worker nodes or replicate services
3. **CI/CD integration**: Automate deployment via GitHub Actions or GitLab CI
4. **Upgrade path**: Update K3s version, test rolling updates
5. **Persistence**: Configure PersistentVolumes for stateful services

## Documentation Links

- Quickstart (Vagrant + Ansible): [docs/QUICKSTART-VAGRANT-ANSIBLE.md](docs/QUICKSTART-VAGRANT-ANSIBLE.md)
- On-prem guide: [docs/on-prem-deployment.md](docs/on-prem-deployment.md)
- Vagrant setup: [vagrant/README.md](vagrant/README.md)
- Kustomize overlays: [kustomize/README.md](kustomize/README.md)
- K3s documentation: https://docs.k3s.io/
- Ansible documentation: https://docs.ansible.com/

---

**Last Updated**: April 2026
