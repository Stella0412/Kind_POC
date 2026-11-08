# Day 3 完成记录：探针加固 + metrics-server + HPA + 阶梯压测

日期：2026-10-31
状态：**已完成**（容量报告已出；发现 adservice OOM 与 frontend CPU 限流两个后续项）
分支：`day3`

## 1. 完成项

- [x] 3.0 Git 基线：Day 0–2 已提交，Day 3 在 `day3` 分支执行
- [x] 3.1 探针加固：readiness/liveness 默认 `timeoutSeconds: 5`；
      adservice/cartservice 增加 startupProbe；revision 8 给所有 `grpc_health_probe`
      加 `-rpc-timeout=5s`；revision 6/8 后新 Pod 冷启动 0 重启
- [x] 3.2 metrics-server v0.9.1：`--kubelet-insecure-tls`；`kubectl top` 可用
- [x] 3.3 HPA：`autoscaling/v2`，frontend min 1 / max 4 / CPU 50%；
      验证 1→4 扩容（HPA 观测起点起约 93 秒；档位开始起约 111 秒）和
      4→1 缩容（约 3.5 分钟）
- [x] 3.4 低思考时间阶梯压测：20 / 50 / 100 用户，每档 3 分钟；
      run2 完整跑完，CSV/日志归档
- [x] 3.5 容量报告：`work/reports/day3-capacity.md`

## 2. 关键改动

| 文件 | 改动 |
|---|---|
| `work/helm/online-boutique/templates/deployment.yaml` | 探针 `merge` 默认 `timeoutSeconds: 5`；autoscaling 开启时省略 `replicas` |
| `work/helm/online-boutique/values.yaml` | adservice/cartservice startupProbe；全部 gRPC 探针 `-rpc-timeout=5s`；frontend autoscaling 配置 |
| `work/helm/online-boutique/templates/hpa.yaml` | 新增 HPA 模板（autoscaling/v2，CPU 目标，扩缩容 behavior） |
| `work/manifests/loadtest/locustfile-fast.py` | `wait_time = between(0.1, 0.3)`，去掉 checkout |
| `work/manifests/loadtest/configmap.yaml` | 将 locustfile 挂进 Job |
| `work/manifests/loadtest/job-stepped.yaml` | 20/50/100 三档；`--exit-code-on-error 0` |
| `work/manifests/metrics-server/install.sh` | metrics-server v0.9.1 + `--kubelet-insecure-tls` 的复现脚本 |

## 3. 压测结果（run2，主数据）

| 用户数 | 请求 | 失败 | RPS | 中位 | P95 | P99 | 最大 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 20 | 4,917 | 0 | 27.43 | 510 ms | 1,000 ms | 1,200 ms | 1,500 ms |
| 50 | 9,912 | 16（0.161%） | 55.22 | 650 ms | 1,400 ms | 1,700 ms | 3,100 ms |
| 100 | 11,996 | 29（0.242%） | 66.84 | 1,200 ms | 2,200 ms | 2,600 ms | 4,500 ms |

- 拐点：50 用户 / 约 55 RPS；100 用户已饱和（吞吐只 +21%，P95 翻到 2.2 s）。
- 45 个失败全部是连接级错误（RemoteDisconnected / ConnectionReset），无 HTTP 5xx；
  时间上与 HPA 缩容、Pod 终止、端点切换重合。
- 吞吐瓶颈：frontend 单 Pod CPU limit 200m，cgroup 生命周期累计 7086/7605 个周期被限流（93.2%）；
  rev8 复测窗口内增量为 +886/+913（97.0%）；压测后 worker 节点 CPU 仅约 1%，
  不是节点资源不足。
- adservice：300Mi 内存 limit，100 用户档 OOMKilled（exit 137），该 Pod 累计重启 4 次
  （run2 期间 +3）；rev8 复测又 OOM 1 次。未转成 frontend 5xx，但说明系统在
  100 用户档并非全健康。
- 压测器自检：100 用户 / 90 秒时 loadgenerator 仅 104–110m（limit 2 CPU），不是瓶颈；
  短跑 RPS 43.61，主要受 1→3 副本冷启动爬坡影响，不作为容量数据。

## 4. 过程问题与修正

1. **Locust 1.3.1 不支持 `--html`**：第一次运行 Job 直接失败；移除 `--html`，保留 `--csv`。
2. **Locust 默认失败退出码 1**：50 用户档 23 个连接失败后 Job 以 exit 1 中止，
   100 用户档未执行；增加 `--exit-code-on-error 0`，失败仍记录并继续下一档。
3. **完成后无法 `kubectl cp`**：容器退出后不能 exec；从 Kind 节点 containerd 快照恢复
   `/tmp/stats-*.csv`，方法见 `work/logs/day3-loadtest-artifacts/README.md`。
4. **adservice OOM 不是探针问题**：探针加固解决了 1 秒超时冷启动重启；
   负载期 OOM 需要提高内存 limit，未在 Day 3 修改。
5. **grpc_health_probe 自身也有 1 秒 RPC 超时**：只改 kubelet `timeoutSeconds` 不够；
   run2 中 recommendationservice 仍出现 `health rpc did not complete within 1s`。
   revision 8 给全部 19 条 gRPC 探针加 `-rpc-timeout=5s`；90 秒 / 100 用户复测
   3,814 请求 / 0 失败（CSV 见 `work/logs/day3-loadtest-artifacts/rev8-retest/`），
   未再出现该 RPC 超时；但复测中 adservice 仍 OOM 一次，说明 OOM 与探针无关。

## 5. 证据

- 容量报告：`work/reports/day3-capacity.md`
- CSV：`work/logs/day3-loadtest-artifacts/run2/`
- HPA 时间线：`work/logs/day3-hpa-watch.log`
- 最终状态：`work/logs/day3-final-state.log`
- 探针前后：`work/logs/day3-probes-red.log`、`work/logs/day3-probes-after-upgrade.log`、
  `work/logs/day3-probes-rpc-upgrade.log`
- 压测器 CPU：`work/logs/day3-loadgenerator-cpu.log`
- metrics-server：`work/logs/day3-metrics-server.log`
- HPA 详情：`work/logs/day3-hpa-describe.log`

> 运行日志、CSV 与截图均已入库，索引见 `work/logs/README.md`。

## 6. 后续（Day 4+ / Day 7 候选）

- 提高 frontend CPU request/limit（建议 200m/500m 或 500m/1），HPA max 提到 8，
  再压测验证；当前 93% 周期被限流。
- adservice 内存 limit 提到 512Mi，消除 OOM。
- cartservice / productcatalog / adservice 扩到 2 副本，降低 `POST /cart` 尾延迟。
- frontend 增加 preStop sleep + `terminationGracePeriodSeconds`，减少缩容时连接重置。
- Day 4 安装 kube-prometheus-stack，用 Grafana 验证 CPU throttling、HPA、P95/P99。
- 压测方法改为每档 5–10 分钟、档间保持负载或预扩容，区分稳态容量与冷启动扩容。
