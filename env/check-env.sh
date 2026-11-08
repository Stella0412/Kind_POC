#!/usr/bin/env bash
# 一键检查 Day 0 环境。输出同时保存到 work/logs/env-report.txt
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh" >/dev/null

OUT="$DOCKER_PROJECT_ROOT/work/logs/env-report.txt"
mkdir -p "$(dirname "$OUT")"

{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
  echo
  echo "--- 工具版本 ---"
  kind version 2>&1
  helm version 2>&1
  kubectl version --client 2>&1 | head -2
  docker --version 2>&1
  git --version 2>&1
  python --version 2>&1
  echo
  echo "--- Docker 状态 ---"
  docker info --format 'ServerVersion={{.ServerVersion}}' 2>&1
  docker info --format 'CPUs={{.NCPU}} MemBytes={{.MemTotal}} Driver={{.Driver}}' 2>&1
  docker info --format 'Mirrors={{json .RegistryConfig.Mirrors}}' 2>&1
  echo
  echo "--- 磁盘 ---"
  df -h /d | tail -1
  echo
  echo "--- 仓库 ---"
  git -C "$DOCKER_PROJECT_ROOT/repos/DevOps-Projects" log -1 --oneline 2>&1
  git -C "$DOCKER_PROJECT_ROOT/repos/microservices-demo" log -1 --oneline 2>&1
  echo
  echo "--- Kubeconfig ---"
  echo "KUBECONFIG=$KUBECONFIG"
  kubectl config get-contexts 2>&1
} | tee "$OUT"
