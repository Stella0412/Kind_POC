#!/usr/bin/env bash
# 部署/升级 Online Boutique Helm release。
# 用法：NAMESPACE=qa-helm TAG=day2 CLUSTER=qa-cluster bash work/scripts/deploy.sh
# RENDER_ONLY=1 时只渲染清单，不连接集群（用于校验 nodeSelector 等参数）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${CI:-}" ] && [ -f "$ROOT/env/env.sh" ]; then source "$ROOT/env/env.sh" >/dev/null; fi

NS="${NAMESPACE:-qa-helm}"
TAG="${TAG:-day2}"
CLUSTER="${CLUSTER:-qa-cluster}"

# 节点名跟随集群名，避免 CLUSTER 覆盖后仍调度到 qa-cluster-worker。
# Helm --set 用 \. 转义 key 中的点。
SET_ARGS=(
  --set "services.frontend.image.repository=local/frontend"
  --set "services.frontend.image.tag=$TAG"
  --set "nodeSelector.kubernetes\.io/hostname=${CLUSTER}-worker"
)

if [ "${RENDER_ONLY:-}" = "1" ]; then
  helm template online-boutique "$ROOT/work/helm/online-boutique" -n "$NS" "${SET_ARGS[@]}"
  exit 0
fi

helm upgrade --install online-boutique "$ROOT/work/helm/online-boutique" \
  -n "$NS" --create-namespace \
  "${SET_ARGS[@]}" \
  --wait --timeout 8m

kubectl rollout status deployment/frontend -n "$NS" --timeout=3m
