#!/usr/bin/env bash
set -euo pipefail

DNS_TEST_IMAGE="${DNS_TEST_IMAGE:-busybox:1.36}"
NAMESPACE="${NAMESPACE:-default}"
CONTROL_VM="${CONTROL_VM:-k3s-control}"
WORKERS_CSV="${WORKERS_CSV:-k3s-worker1,k3s-worker2}"
DNS_IP="${DNS_IP:-10.43.0.10}"
TEST_NAME="${TEST_NAME:-currencyservice.default.svc.cluster.local}"

IFS=',' read -r -a WORKERS <<< "${WORKERS_CSV}"

echo "[dns-heal] check+heal: control_vm=${CONTROL_VM} workers=${WORKERS_CSV} ns=${NAMESPACE}"

check_dns() {
  set +e
  vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl delete pod -n ${NAMESPACE} dns-test --ignore-not-found=true >/dev/null 2>&1 || true"
  vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl run dns-test -n ${NAMESPACE} --image=${DNS_TEST_IMAGE} --restart=Never -- nslookup ${TEST_NAME} ${DNS_IP}" >/dev/null 2>&1
  local rc=$?
  vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl logs -n ${NAMESPACE} dns-test || true"
  vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl delete pod -n ${NAMESPACE} dns-test --ignore-not-found=true >/dev/null 2>&1 || true"
  set -e
  return "${rc}"
}

echo "[dns-heal] pre-check"
if check_dns; then
  echo "[dns-heal] DNS already OK"
  exit 0
fi

echo "[dns-heal] DNS failing; applying recovery steps"

echo "[dns-heal] restart coredns"
vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl rollout restart -n kube-system deploy/coredns || true"
vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl rollout status -n kube-system deploy/coredns --timeout=120s || true"

echo "[dns-heal] restart k3s server on control-plane"
vagrant ssh "${CONTROL_VM}" -c "sudo systemctl restart k3s"

echo "[dns-heal] restart k3s-agent on workers"
for w in "${WORKERS[@]}"; do
  vagrant ssh "${w}" -c "sudo systemctl restart k3s-agent"
done

echo "[dns-heal] post-check"
if check_dns; then
  echo "[dns-heal] OK (DNS recovered)"
  exit 0
fi

echo "[dns-heal] FAIL (DNS still unhealthy after recovery)"
echo "[dns-heal] Next actions: inspect CNI + node networking:"
echo "  - vagrant ssh ${CONTROL_VM} -c 'sudo /usr/local/bin/k3s kubectl get pods -n kube-system -o wide'"
echo "  - vagrant ssh ${CONTROL_VM} -c 'sudo /usr/local/bin/k3s kubectl get endpoints -n kube-system kube-dns -o wide'"
exit 1

