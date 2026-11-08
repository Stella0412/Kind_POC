#!/usr/bin/env bash
# 预拉取 project-41 所需镜像（adservice 已按已知修复改为 v0.3.4）。
# 日志：work/logs/image-pull-day0.log
set -u
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh" >/dev/null

LOG="$DOCKER_PROJECT_ROOT/work/logs/image-pull-day0.log"
mkdir -p "$(dirname "$LOG")"

IMAGES=(
  "gcr.io/google-samples/microservices-demo/adservice:v0.3.4"
  "gcr.io/google-samples/microservices-demo/cartservice:v0.3.1"
  "gcr.io/google-samples/microservices-demo/checkoutservice:v0.3.1"
  "gcr.io/google-samples/microservices-demo/currencyservice:v0.3.1"
  "gcr.io/google-samples/microservices-demo/emailservice:v0.3.1"
  "gcr.io/google-samples/microservices-demo/frontend:v0.3.1"
  "gcr.io/google-samples/microservices-demo/loadgenerator:v0.3.1"
  "gcr.io/google-samples/microservices-demo/paymentservice:v0.3.1"
  "gcr.io/google-samples/microservices-demo/productcatalogservice:v0.3.1"
  "gcr.io/google-samples/microservices-demo/recommendationservice:v0.3.1"
  "gcr.io/google-samples/microservices-demo/shippingservice:v0.3.1"
  "redis:7.4-alpine"
  "busybox:1.36.1"
)

FAILED=()
{
  echo "===== 开始预拉镜像 $(date '+%Y-%m-%d %H:%M:%S') ====="
  for img in "${IMAGES[@]}"; do
    echo
    echo ">>> $img"
    if docker pull "$img" 2>&1 | tail -3; then
      echo "OK   $img"
    else
      echo "FAIL $img"
      FAILED+=("$img")
    fi
  done
  echo
  echo "===== 结束 $(date '+%Y-%m-%d %H:%M:%S') ====="
  if [ ${#FAILED[@]} -eq 0 ]; then
    echo "全部成功"
  else
    echo "失败 ${#FAILED[@]} 个："
    printf '  %s\n' "${FAILED[@]}"
  fi
} | tee "$LOG"

exit ${#FAILED[@]}
