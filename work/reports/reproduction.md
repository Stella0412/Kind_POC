# 30 分钟复现报告

日期：2026-11-01
结论：**从删除集群到真实下单成功，最终脚本实测 190 秒（3 分 10 秒），远低于 30 分钟目标。**
证据：`work/logs/day6-postfix-reproduce.log`（评审加固后的完整输出）、
`work/logs/day5-reproduce.log`（首次验收 209 秒）、`work/logs/day5-cluster-delete.log`（删除记录）。

## 1. 环境

| 项 | 值 |
|---|---|
| 宿主机 | Windows 11（10.0.22631） |
| Docker | Docker Desktop 29.8.2，Linux 容器 |
| Docker VM | 7.6 GiB RAM / 32 vCPU |
| Kind | v0.33.0 |
| Kubernetes | v1.32.2（control-plane + worker） |
| Helm | v4.3.1 |
| 本地镜像 | 13 个（12 个上游 + `local/frontend:day2`） |
| 监控 | 不计入核心复现；`monitoring` 需在复现后另行安装 |

复现脚本：`work/scripts/reproduce.sh`
集群配置：`work/kind/config.yaml`（与上游 kind-config 一致，放在 `work/` 以便 CI 使用）

## 2. 步骤与耗时

以 `kind delete cluster --name qa-cluster` 之后开始计时，脚本内部按阶段打印耗时：

| 步骤 | 命令 / 动作 | 耗时 |
|---|---|---:|
| 创建集群 | `kind create cluster --config work/kind/config.yaml` + 等待两节点 Ready | 44 s |
| 导入镜像 | `load-images.sh`：`docker save --platform linux/amd64` + `kind load image-archive` | 78 s |
| 安装 metrics-server | `kubectl apply` + `--kubelet-insecure-tls` + 等待首次采集 | 34 s |
| 部署应用 | `helm upgrade --install` + `kubectl rollout status` | 25 s |
| 校验 | `verify.sh`（节点、Deployment、Pod、HPA、全部 Endpoints） | 6 s |
| 冒烟 | `smoke-test.sh`（首页 / 商品 / 加购 / 下单） | 3 s |
| **合计** | `reproduce.sh` 内部计时 | **190 s** |

各阶段日志行：

```text
[reproduce] cluster ready: 44s (total 44s)
[reproduce] images loaded: 78s (total 122s)
[reproduce] metrics-server ready: 34s (total 156s)
[reproduce] app deployed: 25s (total 181s)
[reproduce] verify: 6s (total 187s)
[reproduce] smoke: 3s (total 190s)
REPRODUCE_SECONDS=190
REPRODUCE OK
```

首次验收（加固前脚本）为 209 秒，日志 `work/logs/day5-reproduce.log`；
上表是最终脚本的复跑结果，两者都是同一台机器的真实计时，差异主要来自节点启动与镜像导入波动。

## 3. 结果

- 节点：2/2 Ready（v1.32.2）。
- 工作负载：11/11 Pod `Running 1/1`，重启数均为 0。
- Service：11/11 Endpoints 非空。
- HPA：`frontend` 存在，min 1 / max 4，目标 CPU 50%；
  部署完成后 26 秒时 `TARGETS` 短暂为 `<unknown>`（metrics-server 尚未完成首次采集），
  约 1 分钟后变为 `cpu: 1%/50%`。
- 冒烟测试：首页、商品详情、加购、`POST /cart/checkout` 全部成功，
  返回页面包含 “Your order is complete!”。
- `frontend-external` 已在 values 中关闭，最终 Service 列表没有 `<pending>`。

状态日志（首次验收运行）：

- `work/logs/day5-reproduce-nodes.log`
- `work/logs/day5-reproduce-pods.log`
- `work/logs/day5-reproduce-svc.log`
- `work/logs/day5-reproduce-hpa.log`
- `work/logs/day5-reproduce-endpoints.log`

## 4. 失败项与处理

| 现象 | 处理 |
|---|---|
| 复用旧集群的第一次演练只用 97 秒 | 该次不是验收数据；验收前执行 `kind delete cluster`，从零创建后计时（首次 209 秒，加固后复跑 190 秒） |
| 部署后 HPA `TARGETS` 短暂 `<unknown>` | metrics-server 首次采集需要时间，等待约 1 分钟后正常；不影响部署与下单 |
| 监控栈不在本地镜像中 | 未计入核心复现。2026-11-01 已按 Day 4 的 `work/manifests/monitoring/values.yaml` 补装并验证（`work/logs/day6-monitoring-reinstall.log`），仍不计入 190 秒 |

## 5. 结论与优化

- **是否 ≤ 30 分钟：是**，190 秒，约 3.2 分钟。
- 最慢的两步是镜像导入（78 s）和集群创建（44 s），合计占 64%。
- 后续优化：
  1. 把 13 个镜像推到本地 registry，省去 `docker save` / `kind load`；
  2. 预拉 `kindest/node:v1.32.2`（本次已命中本地缓存）；
  3. metrics-server 清单改为仓库内固定版本，避免 GitHub 网络波动；
  4. 监控作为独立可选步骤，不计入 30 分钟核心复现。

## 6. 复现命令

```bash
source /d/docker_project/env/env.sh
kind delete cluster --name qa-cluster
bash /d/docker_project/work/scripts/reproduce.sh
```

预期最后两行：

```text
REPRODUCE_SECONDS=<秒数>
REPRODUCE OK
```
