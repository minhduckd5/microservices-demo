#!/usr/bin/env bash
set -euo pipefail

DNS_TEST_IMAGE="${DNS_TEST_IMAGE:-busybox:1.36}"
NAMESPACE="${NAMESPACE:-default}"
CONTROL_VM="${CONTROL_VM:-k3s-control}"
DNS_IP="${DNS_IP:-10.43.0.10}"
TEST_NAME="${TEST_NAME:-currencyservice.default.svc.cluster.local}"

echo "[dns-check] control_vm=${CONTROL_VM} ns=${NAMESPACE} dns_ip=${DNS_IP} name=${TEST_NAME} image=${DNS_TEST_IMAGE}"

vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl delete pod -n ${NAMESPACE} dns-test --ignore-not-found=true >/dev/null 2>&1 || true"

vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl run dns-test -n ${NAMESPACE} --image=${DNS_TEST_IMAGE} --restart=Never -- nslookup ${TEST_NAME} ${DNS_IP}"

vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl logs -n ${NAMESPACE} dns-test"

vagrant ssh "${CONTROL_VM}" -c "sudo /usr/local/bin/k3s kubectl delete pod -n ${NAMESPACE} dns-test --ignore-not-found=true >/dev/null"

echo "[dns-check] OK"

