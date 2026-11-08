#!/usr/bin/env bash
# 生成自建 frontend 镜像的构建上下文：
#   1. 复制上游源码
#   2. 给 handlers.go 打补丁：本地 Kind 下跳过 metadata.google.internal 的 DNS 探测
#      （该查询在集群内耗时 2-4 秒，会让首页每个请求都阻塞）
# 用法：bash work/docker/frontend/prepare-context.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$ROOT/repos/microservices-demo/src/frontend"
DST="$ROOT/work/docker/frontend/context"

rm -rf "$DST"
mkdir -p "$DST"
cp -r "$SRC"/. "$DST"/

if [ -z "${PYTHON_BIN:-}" ]; then
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then
      PYTHON_BIN="$candidate"
      break
    fi
  done
fi
if [ -z "${PYTHON_BIN:-}" ]; then
  echo "ERROR: no working python3/python found" >&2
  exit 1
fi
"$PYTHON_BIN" - "$DST/handlers.go" <<'PY'
import sys

path = sys.argv[1]
source = open(path, encoding="utf-8").read()

old = (
    '\t// Autodetect GCP\n'
    '\taddrs, err := net.LookupHost("metadata.google.internal.")\n'
    '\tif err == nil && len(addrs) >= 0 {\n'
    '\t\tlog.Debugf("Detected Google metadata server: %v, setting ENV_PLATFORM to GCP.", addrs)\n'
    '\t\tenv = "gcp"\n'
    '\t}\n'
)

new = (
    '\t// Autodetect GCP (patched: skip slow DNS lookup in local clusters)\n'
    '\tvar mdAddrs []string\n'
    '\tvar mdErr error\n'
    '\tif os.Getenv("DISABLE_METADATA_DETECTION") != "1" {\n'
    '\t\tmdAddrs, mdErr = net.LookupHost("metadata.google.internal.")\n'
    '\t}\n'
    '\tif mdErr == nil && len(mdAddrs) > 0 {\n'
    '\t\tlog.Debugf("Detected Google metadata server: %v, setting ENV_PLATFORM to GCP.", mdAddrs)\n'
    '\t\tenv = "gcp"\n'
    '\t}\n'
)

if old not in source:
    raise SystemExit("metadata detection block not found; upstream source changed?")
if "DISABLE_METADATA_DETECTION" not in source:
    open(path, "w", encoding="utf-8").write(source.replace(old, new, 1))
    print("patched:", path)
else:
    print("already patched:", path)
PY

grep -n "DISABLE_METADATA_DETECTION\|LookupHost" "$DST/handlers.go"
echo "build context ready: $DST"
