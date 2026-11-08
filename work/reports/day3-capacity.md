# Day 3 容量报告：探针加固、metrics-server、HPA 与阶梯压测

日期：2026-10-31
环境：Docker Desktop 29.8.2 / Kind `qa-cluster`（1 control-plane + 1 worker）/ Kubernetes v1.32.2
命名空间：`qa-helm`（Helm revision 8；容量数据采集于 revision 7，revision 8 只统一了 gRPC 探针超时）
压测入口：`http://frontend:80`（集群内 Service）
工具：Locust 1.3.1（`loadgenerator:v0.3.1` 内置）

> 本文时间均为本地时间（UTC+8）。原始日志为 UTC，换算关系为 UTC+8。

## 1. 结论摘要

1. **HPA 可用**：frontend 在 20 用户档从 1 副本扩到 4 副本：从 HPA 监控首个采样点
   22:16:21 到 4 个 Pod 出现（22:17:54）约 93 秒，从档位开始（22:16:03）算约 111 秒；
   负载停止后从 4 副本缩回 1 副本，用时约 3.5 分钟。
2. **容量拐点在 50 用户附近**：20 → 50 用户吞吐接近翻倍（27.4 → 55.2 RPS），
   但 P95 从 1.0 s 升到 1.4 s；50 → 100 用户吞吐只增加 21%（55.2 → 66.8 RPS），
   P95 升到 2.2 s、P99 2.6 s，已进入饱和区。
3. **真正的瓶颈是 frontend 单 Pod CPU limit，而不是节点资源**：
   frontend 容器 `cpu.max = 20000 100000`（200m）。长生命周期 Pod 的累计统计为
   7086/7605 个周期被限流（93.2%）；在 revision 8 的 90 秒复测窗口内，同一 Pod
   `nr_periods` 9949→10862（+913）、`nr_throttled` 8889→9775（+886），即
   **97.0% 的周期被限流**。同期 worker 节点 CPU 仅约 1%。
   HPA 早已到 `maxReplicas: 4`，继续加用户只会增加排队和尾延迟。
4. **失败均为连接级错误，不是 HTTP 5xx**：三档共 45 个失败（总请求 26,825，0.168%），
   错误是 `RemoteDisconnected` / `ConnectionResetError`；时间上与 HPA 缩容、Pod 终止、
   端点切换重合。没有观察到 500/502/503。
5. **adservice 在 100 用户档 OOMKilled**：内存 limit 300Mi，14:27:54 UTC 被 OOMKill
   （exit 137）；该 Pod 生命周期内累计重启 4 次（run2 期间新增 3 次）。
   revision 8 后的 90 秒复测中，adservice 再次 OOMKilled（23:03:36，exit 137）。
   它没有转成 frontend 的 HTTP 5xx，但说明“探针加固完成”不等于“系统在负载下健康”；
   建议把 adservice 内存 limit 提到 512Mi。
6. **探针加固分两层完成**：revision 6 解决 kubelet exec 的 1 秒超时；revision 8
   进一步给所有 `grpc_health_probe` 加 `-rpc-timeout=5s`，解决探针工具自身的
   1 秒 RPC 超时。revision 8 后 90 秒 / 100 用户复测：3,814 请求、0 失败、
   42.77 RPS（CSV 见 `work/logs/day3-loadtest-artifacts/rev8-retest/`），
   未再出现 `health rpc did not complete within 1s`。adservice 的负载期重启是
   OOM，不是探针超时。

## 2. 本日变更

### 2.1 探针加固（Helm revision 6 + revision 8）

问题复现（加固前）：

- `adservice`、`cartservice` 各重启 2 次，其余多个服务重启 1 次；
- 事件：`Liveness probe failed: command timed out: "/bin/grpc_health_probe ..." timed out after 1s`；
- 根因有两层：
  1. Kubernetes exec 探针默认 `timeoutSeconds: 1`；
  2. `grpc_health_probe` 自身的 `-rpc-timeout` 默认也是 1 秒。即使 kubelet 给 5 秒，
     健康检查 RPC 仍可能在 1 秒内失败。

修改：

- revision 6：`templates/deployment.yaml` 给所有 readiness/liveness 探针统一设为
  `timeoutSeconds: 5`（模板强制，当前所有服务一致；如需按服务覆盖需改模板）；
  `values.yaml` 给 `adservice`、`cartservice` 增加 `startupProbe`
  （`periodSeconds: 2`、`failureThreshold: 30`、`timeoutSeconds: 5`），
  liveness `failureThreshold` 调为 6，readiness 为 3。
- revision 8：给全部 19 条 `grpc_health_probe` 命令加 `-rpc-timeout=5s`
  （cartservice 之前已有）；`helm upgrade` 后 11 个 Deployment 全部滚动完成。

验证：

- revision 6 新 Pod 启动 31 秒时全部 `1/1 Running`，`RESTARTS 0`；
  kubelet 的 `timed out after 1s` 不再出现。
- run2 100 用户档仍观察到 recommendationservice readiness
  `timeout: health rpc did not complete within 1s`，证明只改 kubelet 超时不够。
- revision 8 后 90 秒 / 100 用户复测：3,814 请求、0 失败、42.77 RPS；
  未再出现 `health rpc did not complete within 1s`。复测中 adservice 仍 OOM 1 次
  （见第 5 节），说明 OOM 与探针超时无关。Pod 启动阶段仍有
  `failed to connect service ... within 1s`，这是 `grpc_health_probe` 的
  connect timeout（默认 1 秒），容器尚未监听，属于预期；本轮未改 connect-timeout。

> 注意：探针加固解决的是“健康检查被 1 秒超时误杀”。adservice 在 100 用户档仍因
> 300Mi 内存上限被 OOMKill（见第 5 节），这是资源限制问题，不是探针问题。

### 2.2 metrics-server（v0.9.1）

- 安装前：`kubectl top nodes` 返回 `error: Metrics API not available`；
- 安装 `metrics-server v0.9.1`，并 patch `--kubelet-insecure-tls`（Kind 自签证书）；
  可复现脚本：`work/manifests/metrics-server/install.sh`；
- 安装后：`kubectl top nodes` / `kubectl top pods -n qa-helm` 均返回数据；
- HPA 首次创建时 `TARGETS` 为 `<unknown>`，约 20 秒后变为 `cpu: 1%/50%`。

### 2.3 HPA（Helm revision 7）

- 新增 `templates/hpa.yaml`：`autoscaling/v2`，仅对 `autoscaling.enabled=true` 的服务渲染；
- frontend 配置：`minReplicas: 1`、`maxReplicas: 4`、CPU 目标 50%；
- 行为：扩容 1 Pod/30s；缩容 1 Pod/60s，稳定窗口 60s；
- 开启 autoscaling 时 Deployment 不再渲染 `replicas` 字段，避免与 HPA 互相覆盖。

## 3. 压测方法

- locustfile：`work/manifests/loadtest/locustfile-fast.py`
  - `wait_time = between(0.1, 0.3)`，任务权重 `GET /` 3、`GET /product/*` 5、`POST /cart` 2；
  - 不包含 `/cart/checkout`，因此本报告不覆盖下单全链路。
- Job：`work/manifests/loadtest/job-stepped.yaml`
  - 20 / 50 / 100 用户三档，spawn rate 10/s，每档 3 分钟，档间 `sleep 120`；
  - `--only-summary --csv=/tmp/stats-$u --exit-code-on-error 0`。
- 入口：集群内 `http://frontend:80`，不经过 port-forward 或浏览器。
- 主数据：run2（完整跑完三档），CSV 在
  `work/logs/day3-loadtest-artifacts/run2/`；run1 只用于交叉验证（见第 8 节）。

> 3 分钟一档包含 HPA 扩容爬坡时间，不是严格稳态；这一点在第 7 节单独说明。

## 4. 阶梯压测结果

数据取自各档 `stats-<users>_stats.csv` 的 `Aggregated` 行。

| 用户数 | 总请求 | 失败 | 失败率 | RPS | 中位 | 平均 | P95 | P99 | 最大 | 结束时副本 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 20 | 4,917 | 0 | 0.000% | 27.43 | 510 ms | 559 ms | 1,000 ms | 1,200 ms | 1,500 ms | 4 |
| 50 | 9,912 | 16 | 0.161% | 55.22 | 650 ms | 726 ms | 1,400 ms | 1,700 ms | 3,100 ms | 4 |
| 100 | 11,996 | 29 | 0.242% | 66.84 | 1,200 ms | 1,283 ms | 2,200 ms | 2,600 ms | 4,500 ms | 4 |

吞吐与延迟的变化：

| 区间 | 用户数变化 | RPS 变化 | 中位延迟变化 | P95 变化 |
|---|---|---:|---:|---:|
| 20 → 50 | +150% | +101% | +27% | +40% |
| 50 → 100 | +100% | +21% | +85% | +57% |

按 Little's Law 估算在途请求（RPS × 平均延迟）：

- 20 用户：27.43 × 0.559 s ≈ **15.3**；
- 50 用户：55.22 × 0.726 s ≈ **40.1**；
- 100 用户：66.84 × 1.283 s ≈ **85.7**。

在途请求数随用户数近似线性增长（每用户约 0.77–0.86），但吞吐只从 27.4 增到 66.8 RPS；
多出来的并发主要转化成了排队/延迟，而不是吞吐。

### 4.1 分接口观察（100 用户档）

| 接口 | 请求数 | 失败 | 中位 | P95 | P99 | 最大 |
|---|---:|---:|---:|---:|---:|---:|
| `GET /` | 3,095 | 6 | 1,300 ms | 1,800 ms | 2,000 ms | 2,400 ms |
| `GET /product/*`（9 个商品合计） | 6,927 | 18 | 1,100 ms | 1,600 ms | 1,900 ms | 3,100 ms |
| `POST /cart` | 1,974 | 5 | 2,000 ms | 2,700 ms | 3,000 ms | 4,500 ms |

`POST /cart` 是最慢的接口：它要经 frontend → cartservice → redis，且 cartservice 只有
1 个副本。它也是 100 用户档尾部延迟的主要来源之一。

### 4.2 压测器自检（90 秒）

为确认瓶颈不是 Locust 自身，在 revision 8 之前单独跑了一次 100 用户 / 90 秒，
并采样 loadgenerator CPU：

- loadgenerator CPU **104–110m**（limit 2 CPU），内存约 50MiB；远未打满；
- HPA 在 90 秒内从 1 副本扩到 3 副本；
- 结果：3,907 请求，0 失败，43.61 RPS，中位 1,900 ms，P95 3,400 ms，最大 4,600 ms。

本日共跑了三次 100 用户 / 90 秒短测，用途不同，不要混用：

| 时间 | 用途 | 请求 | 失败 | RPS | 证据 |
|---|---|---|---:|---:|---:|---|
| 22:36 | 压测器自检（revision 7） | 3,907 | 0 | 43.61 | `work/logs/day3-loadgenerator-cpu.log` |
| 22:46 | revision 8 后首次复测 | 4,116 | 0 | 45.92 | 当时的 Job 控制台输出（未落盘） |
| 23:03 | revision 8 复测（本文引用） | 3,814 | 0 | 42.77 | `work/logs/day3-loadtest-artifacts/rev8-retest/` |

这次短跑的 RPS 低于第 4 节的 3 分钟档，是因为从 1 副本冷启动、HPA 爬坡占了大半时间，
**不能与稳态容量数据直接比较**；它只用于证明“压测器不是瓶颈”以及“冷启动扩容很慢”。

## 5. 失败与异常分析

### 5.1 连接级失败

三档合计 45 个失败，全部是连接级错误：

- `RemoteDisconnected('Remote end closed connection without response')`；
- `ConnectionResetError(104, 'Connection reset by peer')`；
- run1 的 50 用户档还出现过少量 `Connection refused`。

没有 HTTP 500/502/503。结合 HPA 时间线，失败集中在副本数从 4 缩到 2、再扩回 4 的窗口：

- 22:20:30 4→3，22:21:32 3→2；50 用户档 22:21:04 开始，22:21:48 才创建到 4 个 Pod
  （两个新 Pod 为 0/1，尚未 Ready）；
- 22:25:26 4→3，22:26:29 3→2；100 用户档 22:26:04 开始，22:26:44 才创建到 4 个 Pod
  （两个新 Pod 为 0/1，尚未 Ready）。

判断：连接被终止中的 Pod 或短暂无就绪端点的 Service 断开，属于弹性伸缩过程中的
连接抖动，不是应用返回错误。报告只把它归因到“时间重合”，没有逐请求证明到具体 Pod。

### 5.2 adservice OOMKilled

- `adservice` 内存 limit 300Mi；
- 14:27:54 UTC（22:27:54）容器以 **exit 137 / OOMKilled** 结束，正值 100 用户档；
- 压测期间 adservice 累计重启 4 次：run2 开始前已重启 1 次，run2 中新增 3 次；
- revision 8 的新 Pod 在 100 用户负载下 `kubectl top` 显示 **266Mi / 300Mi**，余量很小；
- revision 8 的 90 秒复测中再次 OOMKilled（23:03:36，exit 137），重启 1 次；
  重启后空闲内存约 161Mi；
- 重启后 CPU `nr_throttled 304 / nr_periods 3229`（约 9.4%）。

影响：adservice 重启没有转成 frontend 的 HTTP 5xx（frontend 对广告失败做了降级），
但系统在 100 用户档并不是全健康状态；容量数字应理解为“frontend 仍可服务时的吞吐”，
而不是“所有依赖都健康时的吞吐”。

建议（未在 Day 3 实施）：把 adservice `resources.limits.memory` 提到 512Mi，
requests 提到 256Mi，再复测；如仍 OOM，再检查 JVM 堆参数。

## 6. 资源瓶颈

### 6.1 frontend CPU 被限流

在长生命周期 frontend Pod `frontend-6bc5cfbcd6-tj74z` 上读取 cgroup（22:34 累计值）：

```text
cpu.max:  20000 100000        # 200m
cpu.stat:
  nr_periods    7605
  nr_throttled  7086           # 93.2% 的周期被限流
  throttled_usec 2191251486
```

累计值跨了三次压测，可能被空闲期稀释。为得到负载窗口内的比例，在 revision 8 的
90 秒复测前后对同一 Pod 各读一次（`work/logs/day3-loadtest-artifacts/rev8-retest/before-after.txt`）：

| | nr_periods | nr_throttled | 限流比例 |
|---|---:|---:|---:|
| 复测前（23:02） | 9,949 | 8,889 | 89.3%（生命周期累计） |
| 复测后（23:05） | 10,862 | 9,775 | 90.0%（生命周期累计） |
| **增量（复测窗口）** | **+913** | **+886** | **97.0%** |

即负载期间几乎每个 CFS 周期都被限流，而不是“长尾偶发”。

这说明 frontend 不是“没有请求”，而是“有请求但 CPU 配额被 CFS 反复掐断”。
200m 的硬限制在突发流量下会造成明显的尾延迟；节点本身仍有大量空闲 CPU
（压测后 worker 约 389m/1%，内存 1255Mi/16%）。

HPA 的 CPU 目标是 request 的 50%，即 100m × 50% = 50m；100 用户档 HPA 显示
`cpu: 100%/50%`，平均每 Pod 约 100m，但每个 Pod 的硬上限只有 200m。
**HPA 看到“需要更多副本”，却已经到 `maxReplicas: 4`；即使再加副本，单 Pod 仍会被限流。**

### 6.2 下游单副本

除 frontend 外，其余服务均为 1 副本：

- cartservice 1 副本 → `POST /cart` 在 100 用户档中位 2.0 s；
- adservice 1 副本 + 300Mi → OOM；
- productcatalog / recommendation / currency 等也是单副本。

在本轮压测中，frontend 的 CPU 限流更早成为主瓶颈；下游单副本是第二层瓶颈，
在提高 frontend limit 后会先暴露出来。

## 7. HPA 行为时间线

| 时间（UTC+8） | 事件 |
|---|---|
| 22:16:03 | 20 用户档开始，1 副本 |
| 22:16:52 | 2 副本 |
| 22:17:23 | 3 副本 |
| 22:17:54 | 4 副本（HPA 观测起点起 93 秒；档位开始起 111 秒） |
| 22:19:04 | 20 用户档结束 |
| 22:20:30 | 4→3（档间空闲，开始缩容） |
| 22:21:04 | 50 用户档开始 |
| 22:21:32 | 3→2（缩容尚未结束） |
| 22:21:48 | 4 个 Pod（两个新 Pod 0/1，尚未 Ready） |
| 22:24:04 | 50 用户档结束 |
| 22:25:26 | 4→3 |
| 22:26:04 | 100 用户档开始 |
| 22:26:29 | 3→2 |
| 22:26:44 | 4 个 Pod（两个新 Pod 0/1，尚未 Ready） |
| 22:29:04 | 100 用户档结束 |
| 22:30:38 | 4→3 |
| 22:31:25 | 3→2 |
| 22:32:28 | 2→1（负载结束后约 3.5 分钟回到 minReplicas） |

结论：HPA 的扩缩容策略按配置生效；但 120 秒档间空闲足以触发缩容，
下一档开始时正好处于“缩容中”，造成副本数先降后升和连接抖动。
若要测稳态容量，应让每档更长（5–10 分钟）并在档间保持负载，或临时关闭缩容。

## 8. 与 Day 2 对比

| 指标 | Day 2（10 用户，think 1–10 s） | Day 3（20 用户，think 0.1–0.3 s） |
|---|---:|---:|
| RPS | 2.23 | 27.43 |
| 中位延迟 | 19 ms | 510 ms |
| P95 | 85 ms | 1,000 ms |
| 失败率 | 0% | 0% |

Day 2 的低延迟是因为并发很低（约 2 RPS），请求基本不排队；Day 3 把思考时间降到
0.1–0.3 秒后，frontend 的 200m CPU 配额迅速成为瓶颈，中位延迟上升一个数量级。
这组对比说明：**低并发下的延迟数字不能外推为容量**。

## 9. 容量结论与建议

### 9.1 可运行点

- **若 SLO 是 P95 ≤ 1 s**：20 用户 / 约 27 RPS 是上限（P95 恰好 1.0 s，0 失败）。
- **若接受 P95 ≤ 1.5 s、失败率 < 0.2%**：50 用户 / 约 55 RPS 是可运行点
  （P95 1.4 s，0.161% 连接级失败）。
- **100 用户 / 约 67 RPS 已过拐点**：P95 2.2 s、P99 2.6 s、最大 4.5 s，
  失败率 0.242%，不建议作为常态容量。

### 9.2 提升容量的优先级（均未在 Day 3 验证）

1. **提高 frontend CPU 配额**：request 200m、limit 500m（或 request 500m、limit 1），
   HPA 目标 60–70%，`maxReplicas` 提到 8。当前 93% 周期被限流，这是第一优先级。
2. **adservice 内存 512Mi**：先消除 OOM，再谈 100 用户档的稳定性。
3. **下游扩副本**：cartservice、productcatalogservice、adservice 至少 2 副本；
   `POST /cart` 已是最慢接口。
4. **优雅终止**：给 frontend 加 `preStop` sleep（5–10 秒）和
   `terminationGracePeriodSeconds: 30`，减少缩容时的连接重置。
5. **压测方法**：每档 5–10 分钟，档间保持负载或预扩容；另做一次“冷启动扩容”专项，
   不要把冷启动爬坡混进稳态容量。
6. **Day 4 监控**：用 Prometheus/Grafana 观察 CPU throttling、HPA 副本数、
   P95/P99 和错误率，验证上述调整是否真正提升容量。

## 10. 限制与未验证项

- 单 worker 节点，所有业务 Pod 都调度到 `qa-cluster-worker`；节点级争用可能存在，
  但压测后节点 CPU 仅约 1%，不是本轮主瓶颈。
- 每档 3 分钟包含 HPA 爬坡（20 用户档从档位开始约 111 秒、从 HPA 观测起点约 93 秒
  才到 4 个 Pod），不是严格稳态。
- 档间 120 秒空闲触发缩容，50/100 用户档开始时处于缩容过程（2–3 副本），
  约 44 秒后才创建到 4 个 Pod（新 Pod 尚未 Ready）；因此这两档的失败率包含
  弹性伸缩抖动，不是纯稳态失败率。
- CSV 的 `Aggregated` 与控制台汇总请求数相差 0–13 条（<0.1%），是落盘时间差；
  本文统一使用 CSV。
- 未覆盖 `/cart/checkout` 全链路；下单链路的容量需要单独压测。
- 压测器自检见 4.2：100 用户时 loadgenerator 约 110m/2 CPU，未成为瓶颈；
  但该次只有 90 秒，不能当作容量数据。
- 未安装 Prometheus/Grafana；CPU throttling 来自 cgroup，不是监控面板。
- adservice OOM 未修复；100 用户档的容量数字应视为“带故障降级”的结果。

## 11. 复现与证据

复现：

```bash
source /d/docker_project/env/env.sh

kubectl apply -f work/manifests/loadtest/configmap.yaml
kubectl delete job loadtest-stepped -n qa-helm --ignore-not-found
kubectl apply -f work/manifests/loadtest/job-stepped.yaml
kubectl wait --for=condition=complete job/loadtest-stepped -n qa-helm --timeout=25m

POD=$(kubectl get pod -n qa-helm -l job-name=loadtest-stepped \
  -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$POD" -n qa-helm > work/logs/day3-loadtest-stepped.log
```

CSV 采集注意：容器结束后不能再 `kubectl cp`。可在最后一档结束后的 120 秒
`sleep` 窗口内执行，或从 Kind 节点 containerd 快照恢复：

```bash
docker exec qa-cluster-worker sh -c \
  'find /var/lib/containerd -name "stats-100_stats.csv"'
```

证据文件：

| 文件 | 说明 |
|---|---|
| `work/logs/day3-loadtest-artifacts/run2/*.csv` | 三档 Locust 原始统计/失败/历史数据 |
| `work/logs/day3-loadtest-artifacts/rev8-retest/` | revision 8 后 90 秒 / 100 用户复测：控制台、CSV、cgroup 前后值、adservice 状态 |
| `work/logs/day3-loadtest-artifacts/README.md` | 采集说明与 run1 中止原因 |
| `work/logs/day3-loadtest-stepped.log` | run2 完整控制台输出（本地，gitignored） |
| `work/logs/day3-loadtest-stepped-run1.log` | run1 输出，含 50 用户档 23 失败 |
| `work/logs/day3-hpa-watch.log` | HPA/副本变化时间线 |
| `work/logs/day3-final-state.log` | 压测后 Pod/HPA/top/重启数/探针配置 |
| `work/logs/day3-probes-red.log` | 加固前重启与 1 秒超时事件 |
| `work/logs/day3-probes-after-upgrade.log` | revision 6 后新 Pod 0 重启 |
| `work/logs/day3-probes-rpc-upgrade.log` | revision 8 统一 gRPC RPC 超时 |
| `work/logs/day3-loadgenerator-cpu.log` | 压测器 CPU 采样（90 秒 / 100 用户） |
| `work/logs/day3-metrics-server.log` | metrics-server 安装前后 |
| `work/manifests/metrics-server/install.sh` | metrics-server v0.9.1 复现脚本 |
| `work/logs/day3-hpa-describe.log` | HPA 目标、行为、事件 |
| `work/helm/online-boutique/templates/hpa.yaml` | HPA 模板 |
| `work/helm/online-boutique/templates/deployment.yaml` | 探针默认超时与 replicas 条件渲染 |
| `work/helm/online-boutique/values.yaml` | 探针、HPA、资源参数 |
| `work/manifests/loadtest/job-stepped.yaml` | 阶梯压测 Job |
