# 运行记录归档

本目录保存 Day 0–4 全部可留存的命令输出与运行状态，作为报告结论的原始依据。
自 2026-11-01 起纳入 Git（`.gitignore` 对 `work/logs/**/*.log` 做了白名单），
此前只存在于本机。

约定：

- 文件名前缀是发生当天（`dayN-`），`final-state-all.log` 是当前全量快照。
- 文本均为命令原始输出，不做删改；只有超大 JSON（Prometheus 规则 124 KB）
  在快照里做了摘要，原始文件另存。
- 不含凭据：`work/kubeconfig` 仍被忽略；日志中只有集群内 Pod IP 和节点名。
- 镜像归档（`.tar`，数百 MB）不纳入 Git，按需用 DaoCloud 镜像重新导入。

## 全量快照

| 文件 | 内容 |
|---|---|
| `final-state-all.log` | 2026-11-01 00:05 UTC 的全量状态：Helm release、nodes、所有命名空间 Pod/Deploy/STS/DS/HPA/SVC/PVC、`top`、PrometheusRule、监控 Pod 重启数、Prometheus buildinfo/规则摘要/活动告警、Grafana health |
| `prometheus-rules-all-2026-11-01.json` | Prometheus `/api/v1/rules?type=alert` 原始响应（16 组 / 137 条规则），便于复查每条表达式的 `health` 与 `state` |
| `day4-final-state.log` | Day 4 收尾时的监控栈 Pod、`top`、Helm 状态 |

快照中的关键结果：

- 自定义组 `online-boutique.rules` 三条规则均 `state=inactive`、`health=ok`
  （for 分别为 120s / 300s / 600s）。
- 全集群 137 条规则中 4 条 firing、1 条 pending：
  `Watchdog`、`InfoInhibitor`×2、`CPUThrottlingHigh`（`qa/paymentservice` 与
  kindnet）、`PrometheusNotConnectedToAlertmanagers`（未部署 Alertmanager，预期内）。
- `CPUThrottlingHigh` 与 Day 3 的 CPU limit 结论一致：`paymentservice` 在
  `qa` 命名空间仍有约 33% 的周期被限流。

## Day 0：环境准备

| 文件 | 内容 |
|---|---|
| `kind-create.log` | `kind create cluster --name qa-cluster` 输出 |
| `image-pull-day0.log` | Day 0 预拉 online-boutique 8 个镜像 |
| `env-report.txt` | Docker / kind / kubectl / helm 版本与机器资源 |

## Day 1：手工部署 online-boutique

| 文件 | 内容 |
|---|---|
| `day1-cluster-state.log` | 部署后的 nodes / pods / services 状态 |
| `day1-ledger.md` | Day 1 命令台账 |

## Day 2：镜像自建与 Helm 化

| 文件 | 内容 |
|---|---|
| `day2-build.log` | `docker build` 自建 frontend 镜像的完整输出 |
| `day2-helm-template.log` | 改造后的 Helm chart `template` 渲染结果 |
| `day2-helm-install.log` | revision 1 安装（上游镜像） |
| `day2-helm-upgrade.log` | 升级到自建镜像 |
| `day2-helm-state.log` | `helm history` / `get values` / `status` |
| `day2-verify.log` | rollout 与 HTTP 验证 |
| `day2-loadtest-baseline.log` | 上游镜像基线压测 |
| `day2-loadtest-selfbuilt-v1.log` | 自建镜像 v1 压测 |
| `day2-loadtest-final.log` | 当天最终一轮压测 |
| `day2-loadtest-pods.log` | 一次错误命令（`kubectl --timeout` 用法错误）的原始记录，保留以示过程 |
| `day2-final-state.log` | Day 2 收尾状态 |
| `day2-ledger.md` | Day 2 命令台账 |

## Day 3：探针、metrics-server、HPA 与阶梯压测

| 文件 | 内容 |
|---|---|
| `day3-probes-red.log` | 修改探针前复现的未就绪/重启故障 |
| `day3-probes-upgrade.log` | 加入 startup/readiness/liveness 的 Helm 升级 |
| `day3-probes-after-upgrade.log` | 升级后探针状态 |
| `day3-probes-rpc-upgrade.log` | gRPC 探针调整的升级输出 |
| `day3-metrics-server.log` | metrics-server 安装与 APIService 状态 |
| `day3-metrics-top-nodes.log` | `kubectl top nodes` |
| `day3-metrics-top-pods.log` | `kubectl top pods` |
| `day3-hpa-red.log` | 安装前确认 HPA 不存在的输出 |
| `day3-hpa-upgrade.log` | 应用 HPA 的 Helm 升级 |
| `day3-hpa-status.log` | HPA 从 `<unknown>` 到 `1%` 的就绪过程 |
| `day3-hpa-describe.log` | HPA 事件与指标来源 |
| `day3-hpa-watch.log` | 压测期间 HPA 副本数变化（主记录，55 KB） |
| `day3-hpa-watch-run1.log` | 第一轮观察（37 KB） |
| `day3-hpa-final.yaml` | 最终 HPA 清单 |
| `day3-loadtest-apply.log` | Locust Job 创建 |
| `day3-loadtest-stepped.log` | 阶梯压测主日志（20/50/100 用户） |
| `day3-loadtest-stepped-run1.log` | 第一轮阶梯压测 |
| `day3-loadtest-job-final.yaml` | 阶梯压测 Job 最终清单 |
| `day3-loadgenerator-cpu.log` | 压测器侧 CPU 记录 |
| `day3-restarts-before-load.log` | 压测前各 Pod 重启次数 |
| `day3-restarts-before-load-run2.log` | 第二轮压测前重启次数 |
| `day3-restarts-after-load.log` | 压测后重启次数（adservice 4 次） |
| `day3-final-state.log` | Day 3 收尾状态 |
| `day3-loadtest-artifacts/` | Locust CSV（`rev8-retest`、`run1-partial`、`run2`）与说明 |

关键结果：`rev8-retest/rev8_stats.csv` 记录 3,814 请求 / 0 失败 / 42.77 RPS；
`rev8-retest/before-after.txt` 记录同一 Pod CPU 限流从 9,949/8,889 增至
10,862/9,775（97.0%）以及 adservice OOMKilled（exit 137）。

## Day 4：可观测性与告警

| 文件 | 内容 |
|---|---|
| `day4-monitoring-install.log` | kube-prometheus-stack 安装输出 |
| `day4-alerts.log` | PrometheusRule apply、触发、删除 `alert-test` 的过程 |
| `day4-smoke-load.log` | 50 用户 / 2 分钟冒烟压测（4,284 请求、0 失败、35.85 RPS） |
| `day4-final-state.log` | 监控栈 Pod、`top`、Helm 状态 |
| `final-state-all.log` | 当前全量快照（见上） |
| `prometheus-rules-all-2026-11-01.json` | 全量告警规则原始 JSON |

## 未归档的内容

| 内容 | 原因 |
|---|---|
| `work/kubeconfig` | 集群凭据，禁止入库 |
| `*.tar`（镜像归档，约 653 MB） | 体积过大；用 `docker save` + `kind load image-archive` 可重建 |
| 其他位置的 `*.log` | 仍按 `.gitignore` 忽略，仅本目录留档 |
