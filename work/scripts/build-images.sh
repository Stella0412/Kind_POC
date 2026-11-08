#!/usr/bin/env bash
# 构建自建 frontend 镜像并导入 Kind 集群。
# 用法：TAG=day2 bash work/scripts/build-images.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${CI:-}" ] && [ -f "$ROOT/env/env.sh" ]; then source "$ROOT/env/env.sh" >/dev/null; fi

TAG="${TAG:-day2}"
IMAGE="local/frontend:${TAG}"
CLUSTER="${CLUSTER:-qa-cluster}"

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "ERROR: kind cluster '$CLUSTER' not found; run work/scripts/reproduce.sh or kind create cluster first" >&2
  exit 1
fi

bash "$ROOT/work/docker/frontend/prepare-context.sh"
docker build --platform linux/amd64 \
  -f "$ROOT/work/docker/frontend/Dockerfile.day2" \
  -t "$IMAGE" \
  "$ROOT/work/docker/frontend/context"

ARCHIVE="$ROOT/work/docker/frontend-${TAG}.tar"
docker save --platform linux/amd64 "$IMAGE" -o "$ARCHIVE"
kind load image-archive "$ARCHIVE" --name "$CLUSTER"
rm -f "$ARCHIVE"
echo "built and loaded $IMAGE"
