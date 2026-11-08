# Day 5 完成记录：一键复现与 CI

日期：2026-11-01
状态：**已完成**（本机 `make ci` 通过；删集群后 190 秒复现并真实下单）
分支：`day3`（沿用前几日分支）

## 1. 完成项

- [x] 5.1 脚本化构建 / 部署 / 冒烟 / 校验：`work/scripts/*.sh` + `Makefile`
- [x] 5.1 本地 `make ci` 通过（`VERIFY OK`、`SMOKE OK`，退出码 0）
- [x] 5.1 GitHub Actions 工作流 `.github/workflows/ci.yaml`（**未在远端执行**）
- [x] 5.2 删除 `qa-cluster` 后从零复现，最终脚本实测 **190 秒**（首次验收 209 秒）
- [x] 5.3 `work/reports/rca.md`（8 条 RCA）
- [x] 5.3 `docs/architecture.md`（业务 / 部署 / 排障六层三张图）
- [x] 5.3 `work/reports/reproduction.md`（含真实计时）
- [x] README 增加 Day 5 段落

## 2. 新增 / 修改文件

| 文件 | 说明 |
|---|---|
| `work/scripts/build-images.sh` | 生成构建上下文、构建 `local/frontend:<TAG>`、导入 Kind |
| `work/scripts/deploy.sh` | `helm upgrade --install` + rollout 等待 |
| `work/scripts/smoke-test.sh` | port-forward + 首页/商品/加购/下单真实请求 |
| `work/scripts/verify.sh` | 节点、Pod、HPA、Helm、全部 Service Endpoints |
| `work/scripts/reproduce.sh` | 从零复现全流程，按阶段打印耗时 |
| `work/scripts/load-images.sh` | 检查/拉取 13 个镜像并一次性导入 Kind（复现与 CI 共用） |
| `work/kind/config.yaml` | 双节点 Kind 配置（复制自上游，避免依赖被忽略的 `repos/`） |
| `Makefile` | `build/deploy/smoke/verify/ci/reproduce` |
| `.github/workflows/ci.yaml` | GitHub Actions 工作流（未远端执行） |
| `work/docker/frontend/prepare-context.sh` | 去掉硬编码路径；Python 解释器自动探测 |
| `work/manifests/metrics-server/install.sh` | 等待 Metrics API 首次采集成功（60 秒超时） |
| `work/reports/rca.md` | 8 条 RCA，统一五段式 |
| `docs/architecture.md` | 三张 Mermaid 图 + 排障六层表 |
| `work/reports/reproduction.md` | 30 分钟复现报告 |

## 3. 本机 CI 结果

```text
$ make ci
...
SMOKE OK: homepage / product / cart / checkout
VERIFY OK: all services have endpoints
```

> 上面是加固前 `make ci` 的原始输出；`verify.sh` 评审加固后增加了节点、Deployment、
> Pod 就绪和 HPA 断言，现输出为
> `VERIFY OK: nodes Ready, N pods Running/Ready, HPA frontend, all services have endpoints`。

- 完整日志：`work/logs/day5-ci-local.log`
- 镜像构建命中 Docker 层缓存；`local/frontend:day2` 重新导入成功。
- 部署为 Helm revision 10（复用集群阶段），随后删集群重建为 revision 1。

## 4. 删集群复现结果

最终脚本（评审加固后）复跑：

```text
$ kind delete cluster --name qa-cluster
$ bash work/scripts/reproduce.sh
[reproduce] cluster ready: 44s (total 44s)
[reproduce] images loaded: 78s (total 122s)
[reproduce] metrics-server ready: 34s (total 156s)
[reproduce] app deployed: 25s (total 181s)
[reproduce] verify: 6s (total 187s)
[reproduce] smoke: 3s (total 190s)
REPRODUCE_SECONDS=190
REPRODUCE OK
```

首次验收（加固前脚本）为 209 秒，原始日志 `work/logs/day5-reproduce.log`；
最终复跑日志 `work/logs/day6-postfix-reproduce.log`。

- 11/11 Pod Running，重启数 0；11/11 Service Endpoints 非空。
- 冒烟测试真实走完加购与下单。
- 详细报告：`work/reports/reproduction.md`；原始日志 `work/logs/day5-reproduce.log`，
  最终复跑日志 `work/logs/day6-postfix-reproduce.log`。

## 5. 过程问题与处理

1. **Windows `python3` 是 Microsoft Store 存根**：`python3 -c` 退出码 49，会导致补丁被静默跳过。
   `prepare-context.sh` 改为依次探测可用解释器（先执行 `import sys` 验证）。
2. **CI 无法使用 `repos/` 下的 kind 配置**：`repos/` 被 `.gitignore` 忽略，远端 checkout 不存在。
   复制为受版本管理的 `work/kind/config.yaml`，`reproduce.sh` 与 CI 共用。
3. **metrics-server rollout 完成后 Metrics API 仍未就绪**：`install.sh` 增加最多 60 秒轮询，
   避免 `kubectl top` 立刻失败导致复现中断。
4. **`frontend-external` 在 Kind 下永远是 `<pending>`**：values 改为 `enabled: false`，
   演示统一用 port-forward；因此最终 Service 列表没有 pending 资源。
5. **Docker Desktop 重启后旧 Kind 集群被恢复**：第一次演练复用了旧集群（97 秒），
   不作为验收数据；验收前执行 `kind delete cluster`，从零计时得到 209 秒，
   加固后复跑为 190 秒。
6. **监控未随复现安装**：复现只覆盖核心电商环境；`monitoring` 需另行安装，
   不计入 30 分钟。2026-11-01 为录制视频已按 Day 4 参数补装（见 `notes/day6.md`）。

## 6. 证据索引

- CI 日志：`work/logs/day5-ci-local.log`
- 复现日志：`work/logs/day6-postfix-reproduce.log`、`work/logs/day5-reproduce.log`、
  `work/logs/day5-cluster-delete.log`
- 复现前后状态：`work/logs/day5-before-reproduce-*.log`、`work/logs/day5-reproduce-*.log`
- RCA：`work/reports/rca.md`
- 架构：`docs/architecture.md`
- 复现报告：`work/reports/reproduction.md`

## 7. 未完成 / 明确声明

- GitHub Actions 工作流**只提交了文件，未在远端 push 运行**；简历与报告中不得写“CI 已在 GitHub 跑通”。
- 生产级能力未覆盖：单机 Kind、无外部 LB、无多可用区、无真实告警通知渠道。
- 压测只覆盖读链路与加购，未压 checkout 写链路（沿袭 Day 3 的范围）。

## 7. 评审后加固（2026-11-01）

最终评审未发现 Critical，三条 Important 均已修复并实测：

1. **`CLUSTER` 覆盖失效**：`deploy.sh` 之前不读 `CLUSTER`，chart 固定调度到
   `qa-cluster-worker`。现在用 `--set nodeSelector.kubernetes\.io/hostname=${CLUSTER}-worker`
   跟随集群名；`RENDER_ONLY=1` 可离线渲染核对（`CLUSTER=mycluster` 渲染为
   `mycluster-worker`）。
2. **CI 只预载 frontend**：新增 `work/scripts/load-images.sh`，本地复现与 CI 共用同一条
   13 镜像导入路径；CI 设置 `PULL=1`，先拉取上游镜像（3 次重试）再 `kind load image-archive`，
   避免 11 个镜像在 `helm --wait` 期间由 kubelet 逐个从 gcr.io 拉取。
3. **`verify.sh` 断言过弱**：新增节点 Ready、Deployment rollout、Pod Running/Ready、
   HPA 存在断言。负向测试：构造一个只有 Service 和手工 Endpoints、没有任何 Pod 的命名空间，
   旧脚本输出 `VERIFY OK`（误报），新脚本以 `ERROR: no Running pods` 退出 1。

修复后删除集群重新复现：**190 秒**，11/11 Pod Running、HPA 存在、下单成功；
日志 `work/logs/day6-postfix-reproduce.log`。
