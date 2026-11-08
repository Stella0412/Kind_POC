#!/usr/bin/env bash
# 从零复现 qa-helm 演示环境：
#   kind 集群 -> 导入镜像 -> metrics-server -> Helm 部署 -> 校验 -> 冒烟
# 用法：bash work/scripts/reproduce.sh
# 前置：Docker Desktop 已启动；本地已有项目镜像（缺失时脚本会明确报错）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${CI:-}" ] && [ -f "$ROOT/env/env.sh" ]; then source "$ROOT/env/env.sh" >/dev/null; fi

CLUSTER="${CLUSTER:-qa-cluster}"
NS="${NAMESPACE:-qa-helm}"
TAG="${TAG:-day2}"
KIND_CONFIG="$ROOT/work/kind/config.yaml"

START=$(date +%s)
STEP_START=$START
mark() {
  local now; now=$(date +%s)
  echo "[reproduce] $1: $((now - STEP_START))s (total $((now - START))s)"
  STEP_START=$now
}

echo "[reproduce] start $(date -Is)"

# 1. 集群
if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --config "$KIND_CONFIG"
else
  echo "[reproduce] cluster '$CLUSTER' already exists; reusing it"
fi
kubectl wait --for=condition=ready nodes --all --timeout=240s
mark "cluster ready"

# 2. 镜像
CLUSTER="$CLUSTER" TAG="$TAG" bash "$ROOT/work/scripts/load-images.sh"
mark "images loaded"

# 3. metrics-server（HPA 与 kubectl top 依赖）
bash "$ROOT/work/manifests/metrics-server/install.sh"
mark "metrics-server ready"

# 4. 部署
CLUSTER="$CLUSTER" NAMESPACE="$NS" TAG="$TAG" bash "$ROOT/work/scripts/deploy.sh"
mark "app deployed"

# 5. 校验与冒烟
NAMESPACE="$NS" bash "$ROOT/work/scripts/verify.sh"
mark "verify"
NAMESPACE="$NS" bash "$ROOT/work/scripts/smoke-test.sh"
mark "smoke"

TOTAL=$(( $(date +%s) - START ))
echo "REPRODUCE_SECONDS=${TOTAL}"
echo "REPRODUCE OK"
