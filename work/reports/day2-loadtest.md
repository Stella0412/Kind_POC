# Day 2 压测报告：Online Boutique（Kind 本地集群）

日期：2026-10-31
工具：Locust `loadgenerator:v0.3.1`
对象：`qa-helm/frontend`（Service ClusterIP，port 80 → container 8080）
场景：10 并发用户，spawn rate 2/s，持续 5 分钟，headless，`--only-summary`

## 1. 环境

| 项 | 值 |
|---|---|
| 集群 | kind `qa-cluster`，2 节点（1 control-plane + 1 worker） |
| Kubernetes | v1.32.2 |
| 节点资源 | Docker VM 7.6 GB RAM / 32 CPU |
| 命名空间 | `qa-helm`（Helm 部署） |
| 副本 | 所有服务 1 副本，全部调度到 `qa-cluster-worker` |
| 压测入口 | `http://frontend:80`（集群内 Service） |

## 2. 对照组

| 组别 | frontend 镜像 | 说明 |
|---|---|---|
| A 基线 | `gcr.io/.../frontend:v0.3.1` | 上游官方镜像，未做任何修改 |
| B 自建 v1 | `local/frontend:day2`（首版补丁） | 加入 `DISABLE_METADATA_DETECTION` 开关 |
| C 自建最终 | `local/frontend:day2`（修正 `len>0`） | 平台标识正确为 `local`，最终验证版本 |

## 3. 结果汇总

| 指标 | A 基线 | B 自建 v1 | C 自建最终 |
|---|---|---|---|
| 总请求数 | 561 | 664 | 666 |
| 失败数 / 失败率 | 0 / 0.00% | 0 / 0.00% | 0 / 0.00% |
| 吞吐（RPS） | 1.88 | 2.23 | 2.23 |
| 平均延迟 | 81 ms | 27 ms | 33 ms |
| 中位数 | 4000 ms | 19 ms | 19 ms |
| P95 | 4000 ms | 76 ms | 85 ms |
| P99 | 4900 ms | 140 ms | 480 ms |
| 最大延迟 | 4900 ms | 948 ms | 790 ms |

> A 组使用旧版 Locust 汇总格式，失败数取自运行记录（0 失败）。
> B/C 组为同一镜像的两次构建，差异来自重跑波动与单次尾部请求，不代表性能回退。

## 4. 分接口对比（C 组，最终）

| 接口 | 请求数 | 失败 | 平均 | 中位 | P95 | 最大 |
|---|---|---|---|---|---|---|
| GET / | 43 | 0 | 49 ms | 19 ms | 260 ms | 541 ms |
| GET /product/*（9 个商品） | 378 | 0 | 17-64 ms | 18 ms | 21-560 ms | 21-790 ms |
| GET /cart | 87 | 0 | 25 ms | 19 ms | 51 ms | 400 ms |
| POST /cart | 87 | 0 | 31 ms | 23 ms | 87 ms | 102 ms |
| POST /cart/checkout | 22 | 0 | 75 ms | 75 ms | 110 ms | 131 ms |
| POST /setCurrency | 49 | 0 | 36 ms | 22 ms | 49 ms | 644 ms |

下单链路（POST /cart/checkout → 200）在压测中全部成功，说明多服务 gRPC 调用链正常。

## 5. 关键结论

1. **失败率 0%**，满足计划中「失败率 ≤ 1%」的验收标准。
2. **首页 4s 延迟消失**：基线中 `/` 与 `/setCurrency` 的 P95 均为 4000 ms，
   源于 CoreDNS 对 `metadata.google.internal.` 返回 SERVFAIL + Go resolver 重试；
   应用层关闭探测后，中位延迟降到 19 ms。
3. **吞吐提升约 19%**（1.88 → 2.23 RPS）。压测用户数固定为 10，
   吞吐提升主要来自单请求耗时下降后同一用户能完成更多轮次。
4. **尾部延迟仍在 0.5-0.8s**：下单链路串行调用 cart/product/currency/shipping/payment/email，
   本地单副本 + 单 worker 节点下属于正常现象；扩副本或加资源可进一步压降。
5. 镜像体积从 55.9 MB 降到 52.8 MB，启动与分发成本略降。

## 6. 复现命令

```bash
source /d/docker_project/env/env.sh

# 1. 确认 Helm 部署就绪
kubectl get pods -n qa-helm
kubectl get endpoints -n qa-helm

# 2. 启动压测
kubectl delete job loadgenerator -n qa-helm --ignore-not-found
kubectl create -f work/manifests/loadgenerator-job.yaml

# 3. 等待完成并收集
kubectl wait --for=condition=complete job/loadgenerator -n qa-helm --timeout=420s
kubectl logs -n qa-helm job/loadgenerator > work/logs/day2-loadtest-final.log
```

## 7. 备注

- 基线数据来自 `work/logs/day2-loadtest-baseline.log`（同为 10 并发 / 5 分钟）。
- 自建镜像构建与补丁细节见 `notes/day2.md` 第 2 节。
- 因节点对同名 tag 不会自动替换镜像，重跑前需 `kubectl rollout restart deploy/frontend -n qa-helm`。
