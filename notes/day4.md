# Day 4 完成记录：可观测性与告警

日期：2026-10-31
状态：**已完成**（监控栈运行正常；3 条告警规则已加载，PodCrashLooping 已验证
Pending → Firing → 恢复）
分支：`day3`（沿用 Day 3 分支，Day 4 未单独开分支）

## 1. 完成项

- [x] 4.1 安装前资源预检：worker 内存 1.3 GiB / 7.6 GiB，余量充足
- [x] 4.2 精简版 kube-prometheus-stack 92.16.1（app v0.94.2）：
      Alertmanager 关闭，控制面抓取关闭，Prometheus 保留 6h
- [x] 4.3 Grafana 命名空间看板 + 50 用户 / 2 分钟压测截图
- [x] 4.4 3 条 PrometheusRule + PodCrashLooping 触发与恢复验证
- [x] 4.5 记录与提交

## 2. 关键改动

| 文件 | 说明 |
|---|---|
| `work/manifests/monitoring/values.yaml` | 精简安装参数；Grafana 匿名只读（仅本地 POC） |
| `work/monitoring/alerts.yaml` | `online-boutique-alerts`，3 条规则 |
| `work/screenshots/day4-grafana-frontend.png` | Grafana Namespace (Pods) 看板，压测期间的 CPU 曲线 |
| `work/screenshots/day4-alert-firing.png` | Prometheus Alerts 页面，PodCrashLooping Firing |

## 3. 结果

### 3.1 监控栈

| 组件 | 状态 | 内存 |
|---|---|---:|
| prometheus (v3.15.1) | 2/2 Running，0 重启 | 262 MiB |
| grafana (13.3.0) | 3/3 Running，0 重启 | 592 MiB（含 2 个 sidecar） |
| kube-state-metrics (v2.20.0) | 1/1 Running | 61 MiB |
| prometheus-operator (v0.94.2) | 1/1 Running | 71 MiB |
| node-exporter | 2/2 Running（两节点各一） | 39 MiB |

节点：worker 3.2 GiB / 7.6 GiB（41%），无 OOM/Evicted。

### 3.2 看板与压测

- 看板：**Kubernetes / Compute Resources / Namespace (Pods)**，Namespace `qa-helm`
- 压测：50 用户 / 2 分钟，4,284 请求、0 失败、35.85 RPS、中位 1,100 ms、P95 2,000 ms
- 截图 `day4-grafana-frontend.png` 中 15:31–15:33 UTC 的 CPU 曲线明显抬升，
  同时可见 frontend 扩到 3 个 Pod

### 3.3 告警规则

| 规则 | 表达式要点 | 验证 |
|---|---|---|
| PodCrashLooping | `increase(restarts_total[5m]) > 0`，for 2m | 用 crashloop-demo 触发，Firing 后删除命名空间恢复 |
| PodNotReady | Ready==0 且排除 Succeeded/Failed | 修复了 Job 完成 Pod 的误报（见 4.3） |
| DeploymentReplicasMismatch | spec != available，for 10m | 规则健康，未单独触发 |

- Prometheus 中 `online-boutique.rules` 三条规则均 `health=ok`，当前 `inactive`
- PodCrashLooping：15:38:16 UTC 进入 Pending，约 15:40:16 转 Firing，23:44 截图；
  23:45 删除 `alert-test` 命名空间，约 23:51 恢复 Inactive
- 未部署 Alertmanager，因此没有真实通知渠道

## 4. 过程问题与修正

1. **quay.io 镜像拉取极慢**：node-exporter 13 MB 用了 73 秒，其余镜像 10 分钟仍
   ContainerCreating。改用 DaoCloud 镜像拉取到宿主机，retag 后
   `docker save --platform linux/amd64` + `kind load image-archive`，一次导入 653 MB。
2. **Grafana 13 启动重**：256Mi limit 下启动 3 分钟仍未监听 3000，且两个副本同时启动
   争抢 CPU。把 limit 提到 1 CPU / 512Mi 后 3/3 Ready；实测内存约 592Mi，
   再提到 768Mi 留余量。
3. **PodNotReady 误报**：完成态 Job Pod（`loadtest-*`、`loadgenerator`）永远不是 Ready，
   规则会误报。表达式增加 `unless on(pod, namespace)
   kube_pod_status_phase{phase=~"Succeeded|Failed"} == 1` 后恢复 inactive。
4. **Grafana 匿名访问**：为无头浏览器截图，在 values 中开启 `auth.anonymous`
   （Viewer）。仅适用于本地 POC，生产环境必须关闭。
5. **Prometheus 端口转发会随 Pod 重建断开**：Helm 升级后需重新建立 port-forward。

## 5. 证据

- 安装日志：`work/logs/day4-monitoring-install.log`
- 告警验证：`work/logs/day4-alerts.log`
- 短压测：`work/logs/day4-smoke-load.log`
- 最终状态：`work/logs/day4-final-state.log`
- 截图：`work/screenshots/day4-grafana-frontend.png`、`work/screenshots/day4-alert-firing.png`
- 详细报告：`work/reports/day4-observability.md`

> 运行日志、截图和 YAML 均已入库；完整索引见 `work/logs/README.md`。

## 6. 后续（Day 5+）

- 若要验证通知链路：加回 Alertmanager，配置一个本地 webhook/邮件接收端。
- 压测数据可接入 Grafana：把 Locust CSV 转成 Prometheus 指标，或直接标注压测时间窗。
- Job 增加 `ttlSecondsAfterFinished`，减少完成态 Pod 对 `kubectl get pods` 的干扰。
- 把 `monitoring` 安装写进 Day 5 的复现脚本（可选步骤，不计入 30 分钟核心复现）。
