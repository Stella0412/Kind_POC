#!/usr/bin/env bash
# 把 13 个项目镜像导入 Kind 集群。
# 用法：CLUSTER=qa-cluster TAG=day2 bash work/scripts/load-images.sh
# PULL=1 时先从远程拉取上游镜像（CI 用，带重试）；本地默认只使用已有镜像。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${CI:-}" ] && [ -f "$ROOT/env/env.sh" ]; then source "$ROOT/env/env.sh" >/dev/null; fi

CLUSTER="${CLUSTER:-qa-cluster}"
TAG="${TAG:-day2}"
ARCHIVE="${ARCHIVE:-$ROOT/work/docker/all-images.tar}"
LOCAL_IMAGE="local/frontend:${TAG}"

UPSTREAM_IMAGES=(
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
)
IMAGES=("${UPSTREAM_IMAGES[@]}" "$LOCAL_IMAGE")

if [ "${PULL:-}" = "1" ]; then
  for img in "${UPSTREAM_IMAGES[@]}"; do
    ok=0
    for attempt in 1 2 3; do
      echo "[load-images] pulling $img (attempt $attempt/3)"
      if docker pull --platform linux/amd64 "$img"; then ok=1; break; fi
      sleep 5
    done
    if [ "$ok" -ne 1 ]; then
      echo "ERROR: failed to pull $img after 3 attempts" >&2
      exit 1
    fi
  done
fi

MISSING=()
for img in "${IMAGES[@]}"; do
  docker image inspect "$img" >/dev/null 2>&1 || MISSING+=("$img")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "ERROR: missing local images; pull/build them first:" >&2
  printf '  %s\n' "${MISSING[@]}" >&2
  echo "Hint: bash work/scripts/build-images.sh for local/frontend; env/pull-images.sh for upstream images; PULL=1 to pull upstream images." >&2
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "ERROR: kind cluster '$CLUSTER' not found; run kind create cluster first" >&2
  exit 1
fi

trap 'rm -f "$ARCHIVE"' EXIT
docker save --platform linux/amd64 "${IMAGES[@]}" -o "$ARCHIVE"
kind load image-archive "$ARCHIVE" --name "$CLUSTER"
echo "loaded ${#IMAGES[@]} images into $CLUSTER"
