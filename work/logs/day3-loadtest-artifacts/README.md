# Day 3 压测原始数据

## run2/（报告主数据）

2026-10-31 22:16–22:31（UTC+8）完整跑完 20 / 50 / 100 用户三档，Job `loadtest-stepped` 状态 Complete。

| 文件 | 内容 |
|---|---|
| `stats-20_stats.csv` / `stats-20_failures.csv` | 20 用户档汇总/失败明细 |
| `stats-50_stats.csv` / `stats-50_failures.csv` | 50 用户档 |
| `stats-100_stats.csv` / `stats-100_failures.csv` | 100 用户档 |
| `stats-*_stats_history.csv` | Locust 每秒历史采样 |

每档 `--run-time 3m`，档间 `sleep 120`，locustfile 见
`work/manifests/loadtest/locustfile-fast.py`（等待 0.1–0.3 s）。

采集说明：容器结束后 `kubectl cp` 无法再 exec 进容器，CSV 是从
`qa-cluster-worker` 节点的 containerd 快照中恢复的：

```bash
docker exec qa-cluster-worker sh -c \
  'find /var/lib/containerd -name "stats-100_stats.csv"'
```

因此报告使用 CSV 的 `Aggregated` 行；它与控制台汇总的请求数可能相差
0–13 条（<0.1%），是 CSV 落盘与控制台收尾的时间差。

## run1-partial/（第一次运行，已中止）

第一次运行在 50 用户档出现 23 个连接失败，Locust 1.3.1 默认
`--exit-code-on-error 1`，`set -e` 使 Job 在进入 100 用户档前退出。
该目录只有 20 用户档 CSV，仅作交叉验证；50 用户档的汇总保存在
`work/logs/day3-loadtest-stepped-run1.log`（本地日志，未入库）。

修复：Job 命令增加 `--exit-code-on-error 0`，失败仍计入 CSV 并继续下一档。
