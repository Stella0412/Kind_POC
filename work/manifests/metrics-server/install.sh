#!/usr/bin/env bash
# Install metrics-server v0.9.1 for Kind.
# Kind kubelets use self-signed serving certs, so --kubelet-insecure-tls is required.
set -euo pipefail

VERSION="v0.9.1"
URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/${VERSION}/components.yaml"

kubectl apply -f "${URL}"

# Add the flag only if it is not already present (re-running this script is safe).
if ! kubectl get deployment metrics-server -n kube-system \
  -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--kubelet-insecure-tls'; then
  kubectl patch deployment metrics-server -n kube-system --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi

kubectl rollout status deployment/metrics-server -n kube-system --timeout=3m

# rollout 完成不等于 Metrics API 已就绪；等待第一次采集成功。
for _ in $(seq 1 30); do
  if kubectl top nodes >/dev/null 2>&1; then
    kubectl top nodes
    exit 0
  fi
  sleep 2
done
echo "ERROR: Metrics API not available after 60s" >&2
exit 1
