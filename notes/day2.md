# Day 2 完成记录：自建镜像 + Helm 封装 + 压测

日期：2026-10-31
状态：**已完成**（`qa-helm` 11/11 Pod Running，自建镜像生效，5 分钟压测 0 失败）

## 1. 完成项

- [x] 基于上游源码自建 `local/frontend:day2` 镜像（多阶段构建）
- [x] 定位并修复首页 ~4s 延迟（metadata DNS 探测）
- [x] 将 Day 1 清单封装为 Helm Chart `work/helm/online-boutique`
- [x] values 参数化：镜像 tag、副本数、资源、nodeSelector、端口、环境变量
- [x] `helm lint` / `template` / `install` / `upgrade` / `rollback` / `history` 全流程验证
- [x] `qa-helm` 命名空间 11/11 Pod Running、12/12 Service 有 Endpoints
- [x] loadgenerator 5 分钟压测（10 并发），失败率 0%
- [x] 平台标识由 `Google Cloud` 变为 `local`，证明自建镜像真实生效
- [x] 压测报告 `work/reports/day2-loadtest.md`、截图与日志归档

## 2. 自建镜像

### 2.1 构建方式

- Dockerfile：`work/docker/frontend/Dockerfile.day2`（多阶段：builder + 精简运行时）
- 构建上下文：`work/docker/frontend/prepare-context.sh` 复制源码并给 `handlers.go` 打补丁
- 结果：`local/frontend:day2`，**52.8 MB**（上游 gcr 镜像 55.9 MB，减小 5.5%）

构建过程中遇到：官方 `golang:1.15-alpine` 基础镜像下载仅约 15 KB/s，
改用 `alpine:latest` + `apk add go`（Go 1.26.10）安装工具链，旧模块可正常编译。
`GOPROXY=https://goproxy.cn,direct` 保证依赖拉取速度。

### 2.2 首页 4 秒延迟的根因与修复

现象：压测显示 `/` 与 `/setCurrency` 的 P95 = 4000 ms，其它页面正常。

根因：frontend 启动时执行 `net.LookupHost("metadata.google.internal.")` 探测 GCP 环境。
本地 Kind 集群内 CoreDNS 对该域名返回 SERVFAIL（约 2.4s），Go resolver 重试后总计约 4s；
该探测发生在请求路径上，导致每次首页/币种请求都被阻塞。

处理：

1. 曾尝试修改集群 CoreDNS 配置（增加 hosts 记录），但该操作属于集群级变更，
   在权限校验中被拒绝，**未绕过**；
2. 改为应用层修复：`handlers.go` 中探测逻辑增加 `DISABLE_METADATA_DETECTION` 开关，
   并把 `len(addrs) >= 0`（恒真 bug）改为 `> 0`；
3. Helm values 中为 frontend 注入 `DISABLE_METADATA_DETECTION=1`。

效果：首页平均延迟 **~4.0s → ~20-50ms**，平台标识正确显示 `local`。

### 2.3 镜像导入的一个坑

`kind load image-archive` 对**已存在的同名 tag** 不会替换节点上的旧镜像。
重新构建后即使导入成功，节点仍可能运行旧 digest。解决办法是
`kubectl rollout restart deploy/frontend -n qa-helm` 触发重新调度，
让 Pod 使用更新后的 tag；生产环境应使用不可变 tag（如 git sha）避免此类歧义。

## 3. Helm Chart

目录：`work/helm/online-boutique`

```
Chart.yaml
values.yaml                 # 11 个服务的镜像/端口/环境变量/资源/探针
templates/deployment.yaml   # 遍历 .Values.services 渲染
templates/service.yaml
templates/frontend-external.yaml
templates/redis-pvc.yaml
templates/_helpers.tpl
templates/NOTES.txt
```

- 安装：`helm install online-boutique work/helm/online-boutique -n qa-helm --create-namespace`
- 升级：`--set services.frontend.image.tag=day2`
- 回滚：`helm rollback online-boutique 1 -n qa-helm`（验证成功）
- 最终状态：revision 5 deployed，11 Deployment + 12 Service

## 4. 压测结果（10 并发 / 5 分钟）

| 指标 | 基线（gcr 官方镜像） | 自建镜像（优化后） |
|---|---|---|
| 总请求数 | 561 | 666 |
| 失败数 / 失败率 | 0 / 0.00% | 0 / 0.00% |
| 吞吐 RPS | 1.88 | 2.23 |
| 平均延迟 | 81 ms | 33 ms |
| 中位数 | 4000 ms | 19 ms |
| P95 | 4000 ms | 85 ms |
| P99 | 4900 ms | 480 ms |

结论：失败率 0%，吞吐提升约 19%，中位延迟从 4s 降到 19ms。
P99 仍有个别 ~0.5-0.8s 的尾部请求（下单链路串行调用多个服务），在本地单节点资源下属正常波动。
完整数据见 `work/reports/day2-loadtest.md`。

## 5. 证据文件

- 构建日志：`work/logs/day2-build.log`
- Helm 模板/安装/升级/状态：`work/logs/day2-helm-*.log`
- 压测日志：`work/logs/day2-loadtest-baseline.log`、`day2-loadtest-selfbuilt-v1.log`、`day2-loadtest-final.log`
- 最终状态快照：`work/logs/day2-final-state.log`
- 截图：`work/screenshots/day2-helm-selfbuilt-frontend.png`（平台标识 `local`）

## 6. 访问方式

```bash
source /d/docker_project/env/env.sh
kubectl port-forward -n qa-helm svc/frontend 8081:80
# http://localhost:8081
```

## 7. 遗留与后续

- `qa`（Day 1 手工清单）与 `qa-helm`（Day 2 Helm）并存，便于对比；演示前可只保留一套
- 压测仅覆盖单副本 frontend，扩容/弹性（HPA）留到后续
- 若要把 CoreDNS 方案作为正式交付，应在有集群管理员权限的环境实施，而不是改应用代码
- 后续可补充：多副本 + HPA 压测、Prometheus/Grafana 监控、CI 构建流水线
