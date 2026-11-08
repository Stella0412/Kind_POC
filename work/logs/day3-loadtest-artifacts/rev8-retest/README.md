# revision 8 后 90 秒 / 100 用户复测

日期：2026-10-31 23:02–23:05（UTC+8）
环境：Helm revision 8（19 条 gRPC 探针均带 `-rpc-timeout=5s`），HPA 起始 1 副本。

## 运行方式

用临时 Pod（不是阶梯 Job）跑一次短测，跑完 `sleep 600` 以便在容器退出前取回 CSV：

```bash
locust -f /locust/locustfile-fast.py --host=http://frontend:80 \
  --headless -u 100 -r 10 --run-time 90s --only-summary \
  --csv=/tmp/rev8 --exit-code-on-error 0
```

## 结果

| 指标 | 值 |
|---|---|
| 请求数 | 3,814（CSV）/ 3,840（控制台，差 26 条，落盘时间差） |
| 失败数 | 0 |
| RPS | 42.77（CSV）/ 42.84（控制台） |
| 中位 / P95 / 最大 | 1,900 / 3,200 / 5,191 ms |
| frontend HPA | 1 → 4 副本（90 秒内仍在爬坡） |
| adservice | 复测期间 OOMKilled 1 次（23:03:36，exit 137） |

## 文件

| 文件 | 说明 |
|---|---|
| `locust-console.log` | Locust 完整控制台输出（含 Aggregated 与 Error report） |
| `rev8_stats.csv` | 汇总统计；`rev8_failures.csv` 只有表头，即 0 失败 |
| `rev8_stats_history.csv` | 每秒聚合历史 |
| `before-after.txt` | 同一 frontend Pod 复测前后 `cpu.stat`、adservice 重启数与 lastState、`kubectl top`、HPA |

## 说明

- 该次短测起点为 1 副本，HPA 爬坡占了大半时间，RPS 低于 3 分钟档，**不能作为容量数据**；
  本文数字以 CSV 为准（`Aggregated` 行 3,814 / 42.77），控制台汇总晚于 CSV 落盘，
  相差 26 条；
  只用于验证 revision 8 的探针在 100 用户负载下不再产生 `health rpc did not complete within 1s`。
- adservice 仍 OOM：说明 300Mi limit 不足，与探针超时无关。
- `before-after.txt` 中同一 Pod 的 `nr_periods/nr_throttled` 增量 913/886，即 97.0% 的
  CFS 周期被限流，是第 6.1 节窗口内限流比例的证据。
