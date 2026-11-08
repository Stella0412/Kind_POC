#!/usr/bin/env bash
# 真实走完首页 -> 商品 -> 加购 -> 下单的冒烟测试。
# 用法：NAMESPACE=qa-helm PORT=18080 bash work/scripts/smoke-test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${CI:-}" ] && [ -f "$ROOT/env/env.sh" ]; then source "$ROOT/env/env.sh" >/dev/null; fi

NS="${NAMESPACE:-qa-helm}"
PORT="${PORT:-18080}"
BASE="http://127.0.0.1:${PORT}"
COOKIE="$(mktemp)"

cleanup() { kill "${PF_PID:-}" 2>/dev/null || true; rm -f "$COOKIE"; }
trap cleanup EXIT

kubectl port-forward -n "$NS" svc/frontend "$PORT:80" --address 127.0.0.1 >/dev/null 2>&1 &
PF_PID=$!

ready=0
for _ in $(seq 1 30); do
  if curl -fsS "$BASE/_healthz" >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "ERROR: frontend not reachable via port-forward on $PORT after 30s" >&2
  exit 1
fi

curl -fsS "$BASE/" >/dev/null
curl -fsS "$BASE/product/0PUK6V6EV0" >/dev/null

curl -fsS -c "$COOKIE" -b "$COOKIE" \
  -X POST -d 'product_id=0PUK6V6EV0&quantity=1' \
  "$BASE/cart" >/dev/null

curl -fsS -c "$COOKIE" -b "$COOKIE" \
  -X POST \
  -d 'email=test@example.com' \
  -d 'street_address=1600 Amphitheatre Parkway' \
  -d 'zip_code=94043' \
  -d 'city=Mountain View' \
  -d 'state=CA' \
  -d 'country=United States' \
  -d 'credit_card_number=4432-8015-6152-0454' \
  -d 'credit_card_expiration_month=1' \
  -d 'credit_card_expiration_year=2039' \
  -d 'credit_card_cvv=672' \
  "$BASE/cart/checkout" | grep -qi "Your order is complete"

echo "SMOKE OK: homepage / product / cart / checkout"
