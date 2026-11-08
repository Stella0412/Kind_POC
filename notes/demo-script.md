# Day 6 演示脚本（5–8 分钟）

目标：用一条完整链路讲清“部署 → 验证 → 弹性 → 可观测 → 排障 → 复现”，所有数字都来自 `work/logs/`。
录制时可直接看精简版：`notes/demo-teleprompter.md`。

> 状态：脚本已完成；`work/video/day6-demo.mp4` **尚未录制**（需要本人出镜/口播）。
> 录制后按文末自检清单逐项确认，再在 `notes/day6.md` 勾掉。

## 录制前检查

```bash
source /d/docker_project/env/env.sh
kubectl get nodes
kubectl get pods -n qa-helm
kubectl get hpa -n qa-helm
kubectl get svc -n qa-helm          # 不应有 <pending>
```

- [ ] `qa-helm` 11/11 Running，所有 Service Endpoints 非空
- [ ] `frontend-external` 已关闭（避免 `<pending>`）
- [ ] 终端字号 ≥ 16，关闭个人邮箱/聊天窗口
- [ ] 浏览器标签：`http://localhost:8081`（frontend）、`http://localhost:3000`（Grafana，已重装）
- [ ] 压测数据：2026-11-01 19:18 已跑过 50 用户 / 2 分钟（4,057 请求、0 失败、HPA 到 4），
      Prometheus 保留 6h；超过 6h 再录需重跑（命令见下）

两个端口转发（各开一个终端）：

```bash
kubectl port-forward -n qa-helm svc/frontend 8081:80
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

录制时现场压测（用来实时展示 HPA；约 2 分钟）：

```bash
kubectl apply -f work/manifests/loadtest/configmap.yaml
kubectl apply -f work/manifests/loadtest/job-demo.yaml
kubectl get hpa frontend -n qa-helm -w
```

录制工具：OBS 或 Windows `Win+G`，1080p，麦克风单独音轨。

## 分段脚本

| 时间 | 画面 | 口播要点 |
|---|---|---|
| 0:00–0:40 | README / `docs/architecture.md` | 场景、对象、目标 |
| 0:40–1:30 | `kubectl get nodes/pods/svc` | 双节点、11/11、Endpoints |
| 1:30–2:30 | `helm list`、`helm get values` | 参数化、自建镜像、可回滚 |
| 2:30–4:00 | 浏览器：首页 → 商品 → 加购 → 下单 | 完整下单链路 |
| 4:00–5:30 | 压测 Job + `kubectl get hpa -w` + Grafana | 容量拐点、HPA、限流 |
| 5:30–7:00 | `rca.md`、`reproduction.md` | 六层排障、RCA、复现 |
| 7:00–7:30 | 总结 | 结果、局限、下一步 |

### 0:00–0:40 项目定位

**画面**：`README.md`，滚动到 Day 1–4 段落；可切到 `docs/architecture.md` 的业务链路图。

**口播**：

> 这是一个面向售前演示的 Kubernetes POC。对象是 Google 开源的 Online Boutique，11 个微服务、多语言、gRPC 调用。
> 我要证明三件事：能部署、能排障、能复现。所有结论都有日志和截图，不用“应该可以”这种说法。

### 0:40–1:30 集群与工作负载

**画面**：

```bash
kubectl get nodes -o wide
kubectl get pods -n qa-helm
kubectl get endpoints -n qa-helm
```

**口播**：

> Kind 双节点，control-plane 加一个 worker。11 个业务 Pod 全部 Running，所有 Service 的 Endpoints 非空。
> 这里特意强调：Pod Running 不等于服务可用，Endpoints 有地址才说明它被 Service 纳入了后端。

### 1:30–2:30 Helm 与自建镜像

**画面**：

```bash
helm list -n qa-helm
helm get values online-boutique -n qa-helm | head -40
kubectl get deploy frontend -n qa-helm -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**口播**：

> 11 个服务全部用 Helm 模板化，镜像 tag、资源、副本数、HPA 都是 values 参数。
> frontend 用的是自建镜像 `local/frontend:day2`，52.8 MB；基础镜像是官方 55.9 MB。
> 自建镜像里修了一个本地环境问题：应用启动时会探测 `metadata.google.internal`，在 Kind 里 DNS 超时会让首页每个请求阻塞 4 秒，补丁用环境变量关掉探测。
> Helm 的 revision 可以直接回滚，这是比 `kubectl apply` 更适合交付的地方。

### 2:30–4:00 下单链路

**画面**：浏览器 `http://localhost:8081`：首页 → 点一个商品 → 加入购物车 → 填写测试信息 → 提交订单。

**口播**：

> 下单会经过 frontend、checkout、cart、productcatalog、currency、shipping、payment、email 八个服务。
> checkout 是编排者，任何一跳失败整个订单就失败。Day 1 修的两个问题就在这条链上：
> checkout 的 Service selector 拼错导致没有 Endpoints；payment 的 targetPort 写成 50052，容器实际监听 50051。
> 现在能看到 “Your order is complete”，说明整条链路是通的。

### 4:00–5:30 压测、HPA 与监控

**画面**：`kubectl get hpa -n qa-helm -w`；Grafana Namespace (Pods) 看板（时间范围选最近 5–15 分钟）；`work/reports/day3-capacity.md` 结果表。

**口播**：

> 压测用 Locust，低思考时间 0.1–0.3 秒，20、50、100 用户各 3 分钟。
> 结果：RPS 27.4、55.2、66.8；P95 分别是 1.0、1.4、2.2 秒；失败率 0、0.16%、0.24%，全部是连接级错误，没有 HTTP 5xx。
> 拐点在 50 用户、约 55 RPS。100 用户吞吐只涨 21%，延迟翻倍，说明已经饱和。
> HPA 从 1 扩到 4 用了约 93 秒，缩容回 1 约 3.5 分钟。
> 瓶颈不是节点 CPU，而是 frontend 单 Pod 的 200m CPU limit：cgroup 统计 93% 的周期被限流。这是下一步最该改的参数。

### 5:30–7:00 排障与复现

**画面**：`work/reports/rca.md` 表格；`docs/architecture.md` 排障六层图；`work/reports/reproduction.md` 计时表。

**口播**：

> Day 1 一共修了 6 类清单故障，分布在调度、镜像、准入、服务发现、端口、配置六层；加上 kind 镜像导入和探针/OOM，一共 8 条 RCA，每条都有现象、定位命令、根因、修复和验证。
> 复现不是手工步骤：`work/scripts/reproduce.sh` 从空集群开始，建集群、导入镜像、装 metrics-server、Helm 部署、校验 Endpoints、真实下单。
> 这次删掉集群后的实测总耗时是 190 秒，日志在 `work/logs/day6-postfix-reproduce.log`。

### 7:00–7:30 总结与局限

**口播**：

> 结果：11/11 Running、下单成功、HPA 有扩容证据、3 条告警规则验证过触发和恢复、6 类故障有 RCA、删集群后可一键复现。
> 局限也要说清楚：单机 Kind，不是生产高可用；redis 用 emptyDir，节点重建会丢购物车；没有外部 LB 和真实通知渠道；压测只覆盖读链路和加购，没有压 checkout 写链路。
> 下一步：提高 frontend CPU limit、adservice 内存提到 512Mi、加 preStop 和优雅终止、把复现接进真实 CI。

## 录制后自检

```bash
ls -lh work/video/day6-demo.mp4
```

- [ ] 视频可完整播放，时长 5–8 分钟
- [ ] 无 kubeconfig、密码、个人邮箱
- [ ] 口播数字与 `work/reports/` 一致
- [ ] 没有把“未测”说成“已完成”
