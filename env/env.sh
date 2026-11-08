#!/usr/bin/env bash
# 用法：source /d/docker_project/env/env.sh
# 作用：把 kind / helm 加进当前 shell 的 PATH，并把 kubeconfig 固定在 D 盘。

export DOCKER_PROJECT_ROOT="/d/docker_project"

# Git Bash 的 PATH 必须是 POSIX 路径；Windows 路径里的 "C:" 会被当成 PATH 分隔符。
LOCALAPPDATA_UNIX="$(cygpath -u "$LOCALAPPDATA" 2>/dev/null || echo "$LOCALAPPDATA")"

# kind（winget 安装到 WinGet\Packages\Kubernetes.kind_*）
KIND_PKG="$(ls -d "$LOCALAPPDATA_UNIX"/Microsoft/WinGet/Packages/Kubernetes.kind_*/ 2>/dev/null | head -1)"
if [ -n "$KIND_PKG" ]; then
  export PATH="${KIND_PKG%/}:$PATH"
fi

# helm（winget 安装到 WinGet\Packages\Helm.Helm_*\windows-amd64）
HELM_PKG="$(ls -d "$LOCALAPPDATA_UNIX"/Microsoft/WinGet/Packages/Helm.Helm_*/windows-amd64/ 2>/dev/null | head -1)"
if [ -n "$HELM_PKG" ]; then
  export PATH="${HELM_PKG%/}:$PATH"
fi

# kind/kubectl 是 Windows 程序，KUBECONFIG 要用 Windows 路径。
export KUBECONFIG='D:\docker_project\work\kubeconfig'
mkdir -p "$DOCKER_PROJECT_ROOT/work"

echo "DOCKER_PROJECT_ROOT=$DOCKER_PROJECT_ROOT"
echo "KUBECONFIG=$KUBECONFIG"
echo "kind: $(command -v kind || echo 'not found')"
echo "helm: $(command -v helm || echo 'not found')"
