#!/usr/bin/env bash
# 校验节点、工作负载、HPA、Helm 和所有 Service 的 Endpoints。
# 用法：NAMESPACE=qa-helm bash work/scripts/verify.sh
# REQUIRE_HPA=frontend 时要求该 HPA 存在；REQUIRE_HPA= 可跳过。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${CI:-}" ] && [ -f "$ROOT/env/env.sh" ]; then source "$ROOT/env/env.sh" >/dev/null; fi

NS="${NAMESPACE:-qa-helm}"
REQUIRE_HPA="${REQUIRE_HPA-frontend}"

kubectl get nodes -o wide
kubectl get pods -n "$NS"
kubectl get hpa -n "$NS" || true
helm list -n "$NS"

# 节点必须 Ready。
NOT_READY="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
  | awk 'NF && $2 != "True" {print $1}')"
if [ -n "$NOT_READY" ]; then
  echo "ERROR: nodes not Ready:" >&2
  echo "$NOT_READY" >&2
  exit 1
fi

# 所有 Deployment 必须完成滚动更新。
if ! kubectl rollout status deployment -n "$NS" --timeout=120s; then
  echo "ERROR: deployment rollout did not complete in namespace $NS" >&2
  exit 1
fi

# 每个 Pod 必须是 Running 且所有容器 Ready；已完成的 Job Pod（Succeeded）跳过。
PODS="$(kubectl get pods -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{range .status.containerStatuses[*]}{.ready}{","}{end}{"\n"}{end}')"
RUNNING=0
while IFS='|' read -r pod phase ready; do
  [ -z "$pod" ] && continue
  case "$phase" in
    Succeeded) continue ;;
    Running)
      RUNNING=$((RUNNING + 1))
      if [ -z "$ready" ] || printf '%s' "$ready" | grep -q 'false'; then
        echo "ERROR: pod/$pod is Running but not all containers are Ready (ready=$ready)" >&2
        exit 1
      fi
      ;;
    *)
      echo "ERROR: pod/$pod phase=$phase (expected Running)" >&2
      exit 1
      ;;
  esac
done <<< "$PODS"

if [ "$RUNNING" -eq 0 ]; then
  echo "ERROR: no Running pods in namespace $NS" >&2
  exit 1
fi

# HPA 必须存在，否则 HPA 相关证据不成立。
if [ -n "$REQUIRE_HPA" ] && ! kubectl get hpa "$REQUIRE_HPA" -n "$NS" >/dev/null 2>&1; then
  echo "ERROR: HPA/$REQUIRE_HPA not found in namespace $NS" >&2
  exit 1
fi

for svc in $(kubectl get svc -n "$NS" -o jsonpath='{.items[*].metadata.name}'); do
  ep="$(kubectl get endpoints "$svc" -n "$NS" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  if [ -z "$ep" ]; then
    echo "ERROR: empty endpoints for service/$svc" >&2
    exit 1
  fi
done

echo "VERIFY OK: nodes Ready, $RUNNING pods Running/Ready, HPA ${REQUIRE_HPA:-skipped}, all services have endpoints"
