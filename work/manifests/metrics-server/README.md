# metrics-server（Kind 环境）

## 用途

为 HPA 和 `kubectl top` 提供 Metrics API。没有它时：

```text
$ kubectl top nodes
error: Metrics API not available
```

## 安装（已验证）

```bash
bash work/manifests/metrics-server/install.sh
```

脚本执行：

1. 安装上游 `components.yaml`，固定版本 **v0.9.1**；
2. 给 Deployment 追加 `--kubelet-insecure-tls`（Kind kubelet 使用自签证书，
   不加该参数会报 `x509: certificate signed by unknown authority`）；
3. 等待 rollout，并执行 `kubectl top nodes` 验证。

安装后本环境结果：

```text
NAME                       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
qa-cluster-control-plane   193m         0%       593Mi           7%
qa-cluster-worker          680m         2%       1084Mi          13%
```

## 备用安装（未在本环境使用）

若 GitHub release 下载失败，可用 Helm Chart：

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system -f work/manifests/metrics-server/values.yaml
```

## 注意

- 该组件只用于本地 Kind POC；生产环境应使用集群已有的 metrics 方案，
  不要照搬 `--kubelet-insecure-tls`。
- 删除 Kind 集群会同时删除 metrics-server，Day 5 的一键复现脚本需要重新安装。
