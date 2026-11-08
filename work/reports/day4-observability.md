# Day 4 可观测性与告警报告

日期：2026-10-31
环境：Docker Desktop 29.8.2 / Kind `qa-cluster`（control-plane + worker）/ Kubernetes v1.32.2
监控命名空间：`monitoring`
业务命名空间：`qa-helm`（Helm revision 8）
栈版本：kube-prometheus-stack **92.16.1**（app v0.94.2）

## 1. 结论摘要

1. **监控栈精简部署成功**：Prometheus、Grafana、kube-state-metrics、operator、
   两个 node-exporter 全部 Running/Ready，0 重启、无 OOM/Evicted。
2. **Grafana 能看到压测窗口**：Namespace (Pods) 看板选择 `qa-helm`，
   50 用户 / 2 分钟压测期间 CPU 曲线明显抬升，HPA 从 1 扩到 3 个 frontend Pod。
3. **3 条告警规则已加载**：`online-boutique-alerts` 的
   `PodCrashLooping` / `PodNotReady` / `DeploymentReplicasMismatch`
   在 Prometheus 中 `health=ok`。
4. **告警触发与恢复已验证**：用 `crashloop-demo` 触发 `PodCrashLooping`，
   15:38:16 UTC 进入 Pending，约 2 分钟后 Firing（截图），删除命名空间后恢复 Inactive。
5. **发现并修正一条误报**：`PodNotReady` 会把已完成的 Job Pod 判为未就绪，
   表达式已排除 `Succeeded|Failed`。
6. 未部署 Alertmanager：本轮只验证规则状态与触发，没有真实通知渠道。

## 2. 安装前预检

| 项目 | 结果 |
|---|---|
| worker 已用内存 | 1.3 GiB / 7.6 GiB（17%） |
| control-plane 已用内存 | 645 MiB / 7.6 GiB（8%） |
| D 盘剩余 | 约 415 GB |
| 节点压力 | MemoryPressure / DiskPressure / PIDPressure 均为 False |

余量足够，未删除 Day 1 的 `qa` 命名空间。

## 3. 安装

### 3.1 参数

`work/manifests/monitoring/values.yaml`：

- `alertmanager.enabled=false`（本地无通知渠道）
- `prometheus.retention=6h`，requests 200m/512Mi，limits 1 CPU/1Gi
- `grafana` requests 100m/128Mi，limits 1 CPU/768Mi
- `prometheus-node-exporter` limits 64Mi；`kube-state-metrics` requests 64Mi
- `kubeEtcd` / `kubeControllerManager` / `kubeScheduler` / `kubeProxy` 关闭
- `grafana.ini.auth.anonymous` 开启（Viewer，仅供本地无头截图）

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f work/manifests/monitoring/values.yaml --timeout 10m
```

### 3.2 镜像拉取的现实问题

`quay.io` 在本网络下极慢：node-exporter（13 MB）耗时 73 秒，其余镜像
10 分钟后仍停在 `ContainerCreating`。处理方式：

```bash
# 宿主机通过 DaoCloud 镜像拉取，再 retag 成原镜像名
docker pull quay.m.daocloud.io/prometheus/prometheus:v3.15.1-distroless
docker tag  quay.m.daocloud.io/prometheus/prometheus:v3.15.1-distroless \
            quay.io/prometheus/prometheus:v3.15.1-distroless

# 6 个镜像合并导入 Kind（653 MB）
docker save --platform linux/amd64 <images> -o work/logs/monitoring-images.tar
kind load image-archive work/logs/monitoring-images.tar --name qa-cluster
```

导入后删除卡在拉取的 Pod，让它们用本地镜像重建。

## 4. 监控栈状态

### 4.1 Pod

| Pod | Ready | 重启 | 内存 |
|---|---|---:|---:|
| `prometheus-monitoring-kube-prometheus-prometheus-0` | 2/2 | 0 | 262 MiB |
| `monitoring-grafana-*` | 3/3 | 0 | 592 MiB（含 2 sidecar） |
| `monitoring-kube-state-metrics-*` | 1/1 | 0 | 61 MiB |
| `monitoring-kube-prometheus-operator-*` | 1/1 | 0 | 71 MiB |
| `monitoring-prometheus-node-exporter-*` ×2 | 1/1 | 0 | 39 MiB |

节点：worker 3.2 GiB / 7.6 GiB（41%），control-plane 1.5 GiB / 7.6 GiB（20%）。

### 4.2 Grafana 调整

Grafana 13.3.0 比旧版本重：256Mi limit 下启动超过 3 分钟仍未监听 3000；
两个副本同时启动时各占约 500m CPU，互相拖慢。调整：

1. limits 改为 1 CPU / 512Mi → 3/3 Ready；
2. 实测内存约 592Mi（含 sidecar），再提到 **768Mi** 留余量。

## 5. 看板证据

- 看板：**Kubernetes / Compute Resources / Namespace (Pods)**
  （UID `85a562078cdf77779eaa1add43ccec1e`）
- Namespace：`qa-helm`，时间范围最近 15 分钟
- 截图：`work/screenshots/day4-grafana-frontend.png`

截图中可看到：

- CPU Usage 在 15:31–15:33 UTC 明显抬升，对应 50 用户压测；
- CPU Quota 表列出 adservice、checkoutservice、frontend 等 Pod 的用量/配额；
- Memory Usage 中 adservice 约 246–255 MiB（300Mi limit），与 Day 3 的 OOM 结论一致；
- frontend 出现 3 个 Pod（HPA 扩容中）。

### 5.1 压测数据

| 指标 | 值 |
|---|---|
| 用户数 / 时长 | 50 / 2 分钟 |
| 请求数 | 4,284 |
| 失败数 | 0 |
| RPS | 35.85 |
| 中位 / P95 / 最大 | 1,100 / 2,000 / 3,900 ms |

> 这是 30 秒爬坡 + 120 秒运行的短测，不与 Day 3 的 3 分钟档对比。

## 6. 告警规则

文件：`work/monitoring/alerts.yaml`（PrometheusRule `online-boutique-alerts`，
label `release: monitoring`，与 Prometheus 的 `ruleSelector` 匹配）。

| 规则 | 表达式 | for | 说明 |
|---|---|---|---|
| PodCrashLooping | `increase(kube_pod_container_status_restarts_total{namespace=~"qa-helm\|alert-test"}[5m]) > 0` | 2m | 5 分钟内有重启 |
| PodNotReady | `kube_pod_status_ready{condition="true", namespace="qa-helm"} == 0`，排除 `Succeeded\|Failed` | 5m | 持续未就绪 |
| DeploymentReplicasMismatch | `kube_pod...spec_replicas != status_replicas_available` | 10m | 副本不一致 |

### 6.1 加载验证

```text
online-boutique.rules
  PodCrashLooping              inactive ok
  PodNotReady                  inactive ok
  DeploymentReplicasMismatch   inactive ok
```

### 6.2 触发与恢复

触发对象：`alert-test/crashloop-demo`（busybox:1.36.1，`sh -c 'echo boom; exit 1'`）。

| 时间（UTC） | 事件 |
|---|---|
| 15:36 左右 | 创建 Deployment，Pod 进入 CrashLoopBackOff |
| 15:38:16 | `PodCrashLooping` 进入 Pending |
| 约 15:40:16 | 满足 `for: 2m`，转 Firing |
| 23:44（本地） | 截图 `day4-alert-firing.png`，规则组显示 FIRING (1) |
| 15:45:02 | 删除 `alert-test` 命名空间 |
| 约 15:51 | 恢复 Inactive（5 分钟窗口内不再有重启） |

截图同时可见上游 chart 自带的 `KubePodCrashLooping` 处于 Pending，说明两套规则
对同一故障都生效；自定义规则更简单，便于在面试中解释。

### 6.3 发现的误报

初版 `PodNotReady` 对 `qa-helm` 所有 `Ready==0` 的 Pod 生效，包括已完成的
`loadtest-stepped-*`、`loadtest-smoke-*`、`loadgenerator-*`。这些 Pod 永远不会 Ready，
规则在测试中进入 Pending。修正为：

```promql
kube_pod_status_ready{condition="true", namespace="qa-helm"} == 0
unless on(pod, namespace) kube_pod_status_phase{phase=~"Succeeded|Failed"} == 1
```

修改后 `PodNotReady` 恢复 inactive。

## 7. 资源与局限

- 监控栈总量约 **1.0 GiB**（Grafana 592 + Prometheus 262 + 其他 170），
  节点仍有约 4.4 GiB 余量。
- 单 worker 节点，Prometheus 与业务 Pod 共享 CPU/内存；压测时监控数据本身会占用资源。
- Prometheus 只保留 6h，重启后短期数据丢失；未配置持久卷。
- 未部署 Alertmanager，没有邮件/IM 通知；告警只停留在 Prometheus 内部状态。
- Grafana 匿名 Viewer 仅限本地 POC；截图使用的是匿名访问。
- Kind 节点镜像来自 DaoCloud 镜像站，属于环境适配，不是生产做法。

## 8. 复现

```bash
source /d/docker_project/env/env.sh

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f work/manifests/monitoring/values.yaml --timeout 10m

kubectl apply -f work/monitoring/alerts.yaml
kubectl get prometheusrule -n monitoring online-boutique-alerts

kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# http://localhost:3000/d/85a562078cdf77779eaa1add43ccec1e
#   ?orgId=1&var-namespace=qa-helm&from=now-15m&to=now

kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# http://localhost:9090/alerts?search=PodCrashLooping
```

## 9. 证据文件

| 文件 | 说明 |
|---|---|
| `work/screenshots/day4-grafana-frontend.png` | Grafana 看板，压测期间 CPU 曲线 |
| `work/screenshots/day4-alert-firing.png` | Prometheus Alerts，PodCrashLooping Firing |
| `work/logs/day4-monitoring-install.log` | Helm 安装输出 |
| `work/logs/day4-alerts.log` | 规则 apply、触发、删除命名空间 |
| `work/logs/day4-smoke-load.log` | 50 用户 / 2 分钟 Locust 输出 |
| `work/logs/day4-final-state.log` | 最终 Pod/top/Helm 状态 |
| `work/logs/final-state-all.log` | 2026-11-01 全量状态与告警快照 |
| `work/logs/prometheus-rules-all-2026-11-01.json` | Prometheus 全量规则原始 JSON |
| `work/manifests/monitoring/values.yaml` | 安装参数 |
| `work/monitoring/alerts.yaml` | 告警规则 |
