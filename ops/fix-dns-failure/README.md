# Fix: in-cluster DNS failures (k3s / flannel / CoreDNS)

## Use case

Use this when the Online Boutique frontend (or any pod) fails with errors like:

- `dns: A record lookup error: lookup <service> on 10.43.0.10:53: dial udp 10.43.0.10:53: i/o timeout`
- `could not retrieve currencies`

This is **not** an application bug. It indicates **cluster DNS is unreachable** (typically due to CNI / cross-node pod networking issues) even though `kube-dns` / `coredns` may appear `Running`.

## What this does

- **Validates DNS** by creating a short-lived `busybox` pod and running `nslookup` against `kube-dns` (`10.43.0.10`).
- If DNS fails, performs a **safe, targeted recovery**:
  - restarts **CoreDNS**
  - restarts **k3s** on the control-plane and **k3s-agent** on workers (via `vagrant ssh`)
  - re-runs DNS validation

## Requirements

- Run from the repo root on the host where Vagrant runs.
- VMs up and reachable: `vagrant status`
- You can `vagrant ssh` into nodes (default user: `vagrant`)

## Run

### Check only

```bash
bash ops/fix-dns-failure/dns-check.sh
```

### Check + heal

```bash
bash ops/fix-dns-failure/dns-heal.sh
```

## Notes

- The scripts use `sudo k3s kubectl` (not `kubectl`) because `kubectl` may not be installed on the VM.
- The diagnostic pod image is `busybox:1.36` (override with `DNS_TEST_IMAGE` env var if needed).

