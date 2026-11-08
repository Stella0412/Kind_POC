# Docker + Kubernetes 售前项目实验环境

目标：一周内完成 Online Boutique 11 个微服务在本地 Kind 集群的部署与排障、
Docker 镜像构建、Helm 封装，并产出可演示的 POC 材料和简历项目。

## 目录结构

```
D:\docker_project\
├── env\                 环境脚本与检查
│   ├── env.sh           设置 PATH / KUBECONFIG（每次新终端先 source）
│   ├── check-env.sh     一键检查工具与 Docker 状态
│   └── pull-images.sh   预拉取项目所需镜像
├── repos\               源码仓库
│   ├── DevOps-Projects\            实验仓库（已 sparse 到 project-41）
│   └── microservices-demo\         Online Boutique 源码（v0.3.4）
├── work\                自己产生的所有产物
│   ├── manifests\       修复后的 K8s 清单
│   ├── helm\            Helm Chart
│   ├── screenshots\     截图证据
│   ├── video\           演示视频
│   ├── logs\            命令输出与排障日志
│   ├── reports\         压测与验证报告
│   └── kubeconfig       Kind 集群配置（创建集群后生成）
└── notes\               每日记录
    ├── day0.md
    ├── day1.md / day1-plan.md
    └── day2.md / day2-plan.md
```

## 每次打开新终端

Git Bash：

```bash
source /d/docker_project/env/env.sh
```

PowerShell：

```powershell
. D:\docker_project\env\env.ps1
```

> `env.sh` / `env.ps1` 的核心作用是把 `KUBECONFIG` 指到 `D:\docker_project\work\kubeconfig`，
> 避免集群配置写到 C 盘。kind/helm 已由 winget 写入用户 PATH，新终端可直接使用。

## 环境状态（Day 0 已完成）

| 组件 | 版本 / 状态 |
|---|---|
| Docker Desktop | 29.8.2，Linux 容器，运行中 |
| Docker VM | 7.6 GB RAM / 32 CPU |
| Docker 数据目录 | `D:\DockerData\DockerDesktopWSL`（已在 D 盘） |
| kind | v0.33.0 |
| Helm | v4.3.1 |
| kubectl | v1.36.1 |
| D 盘剩余 | 约 426 GB |
| 镜像仓库 | Docker Hub 走 `hub.rat.dev` / `docker.m.daocloud.io`；gcr.io 直连可用 |
| 项目镜像 | 13 个已全部预拉成功 |
| Kind 集群 | `qa-cluster` 已创建，2 节点 Ready（v1.32.2） |
| Kubeconfig | `D:\docker_project\work\kubeconfig` |

## Day 1 已完成（2026-10-31）

11 个微服务已全部部署到 `qa` 命名空间并运行正常，前端下单链路验证通过。

- 完成记录：`notes/day1.md`
- 排障文档：`work/manifests/SOLUTION.md`
- 修复后清单：`work/manifests/deploy/`
- 截图证据：`work/screenshots/day1-frontend-home.png`

访问方式：

```bash
source /d/docker_project/env/env.sh
kubectl port-forward -n qa svc/frontend 8080:80
# 浏览器打开 http://localhost:8080
```

> 注意：本机 Docker 29 使用 containerd 镜像存储，`kind load docker-image` 会因多平台 index 缺失
> 报 `content digest not found`。请改用：
> `docker save --platform linux/amd64 <images> -o x.tar && kind load image-archive x.tar --name qa-cluster`。

## Day 2 已完成（2026-10-31）

完成自建镜像、Helm 封装与 5 分钟压测，`qa-helm` 命名空间 11/11 Pod Running。

- 完成记录：`notes/day2.md`
- 压测报告：`work/reports/day2-loadtest.md`
- Helm Chart：`work/helm/online-boutique/`
- 自建镜像：`local/frontend:day2`（52.8 MB，基于上游源码 + metadata 探测补丁）
- 截图证据：`work/screenshots/day2-helm-selfbuilt-frontend.png`（平台标识 `local`）

访问方式：

```bash
source /d/docker_project/env/env.sh
kubectl port-forward -n qa-helm svc/frontend 8081:80
# 浏览器打开 http://localhost:8081
```

压测结果（10 并发 / 5 分钟）：

| 指标 | 官方镜像基线 | 自建镜像 |
|---|---|---|
| 请求数 / 失败率 | 561 / 0% | 666 / 0% |
| RPS | 1.88 | 2.23 |
| 中位延迟 | 4000 ms | 19 ms |
| P95 | 4000 ms | 85 ms |

> 首页 4s 延迟根因是 CoreDNS 对 `metadata.google.internal.` 返回 SERVFAIL，
> 已在应用层通过 `DISABLE_METADATA_DETECTION=1` 关闭探测（集群级 CoreDNS 变更因权限被拒绝，未绕过）。

> 注意：`kind load image-archive` 不会替换节点上已存在的同名 tag；
> 重建镜像后需 `kubectl rollout restart deploy/frontend -n qa-helm`。

## Day 3 已完成（2026-10-31）

完成探针加固、metrics-server、HPA 与 20/50/100 用户阶梯压测，容量拐点已定位。

- 完成记录：`notes/day3.md`
- 容量报告：`work/reports/day3-capacity.md`
- 原始数据：`work/logs/day3-loadtest-artifacts/run2/`
- 新增：`work/helm/online-boutique/templates/hpa.yaml`（autoscaling/v2）
- 新增：`work/manifests/loadtest/`（低思考时间 locustfile + 阶梯压测 Job）
- 新增：`work/manifests/metrics-server/install.sh`（metrics-server v0.9.1 复现脚本）

压测结果（run2，每档 3 分钟）：

| 用户数 | 请求数 / 失败率 | RPS | 中位 | P95 | P99 | 副本 |
|---:|---|---:|---:|---:|---:|---:|
| 20 | 4,917 / 0% | 27.43 | 510 ms | 1,000 ms | 1,200 ms | 4 |
| 50 | 9,912 / 0.161% | 55.22 | 650 ms | 1,400 ms | 1,700 ms | 4 |
| 100 | 11,996 / 0.242% | 66.84 | 1,200 ms | 2,200 ms | 2,600 ms | 4 |

关键结论：

- 探针加固分两层：kubelet exec 超时 5 秒 + `grpc_health_probe -rpc-timeout=5s`；
  Helm revision 8，冷启动 0 重启；
- HPA 1→4 扩容约 93 秒（从档位开始算 111 秒），4→1 缩容约 3.5 分钟；
- 50 用户 / 约 55 RPS 是拐点，100 用户已饱和（吞吐只 +21%，P95 2.2 s）；
- frontend 单 Pod CPU limit 200m，cgroup 生命周期 93.2% 周期被限流；
  rev8 复测窗口内为 97.0%；节点 CPU 仅约 1%，瓶颈在 Pod 配额而非节点资源；
- 45 个失败全部是连接级错误，无 HTTP 5xx，与 HPA 缩容/Pod 终止时间重合；
- adservice 300Mi 内存在 100 用户档 OOMKilled（exit 137），该 Pod 累计重启 4 次；
  rev8 复测中再次 OOM，建议后续把 limit 提到 512Mi；
- rev8 复测（90 秒 / 100 用户）：3,814 请求、0 失败，
  数据见 `work/logs/day3-loadtest-artifacts/rev8-retest/`。

访问方式不变：

```bash
source /d/docker_project/env/env.sh
kubectl port-forward -n qa-helm svc/frontend 8081:80
# 浏览器打开 http://localhost:8081
```

## Day 4 已完成（2026-10-31）

kube-prometheus-stack 精简部署完成，Grafana 可见压测曲线，3 条告警规则已加载并验证触发/恢复。

- 完成记录：`notes/day4.md`
- 详细报告：`work/reports/day4-observability.md`
- 安装参数：`work/manifests/monitoring/values.yaml`
- 告警规则：`work/monitoring/alerts.yaml`
- 截图证据：`work/screenshots/day4-grafana-frontend.png`（压测期间 CPU）、
  `work/screenshots/day4-alert-firing.png`（PodCrashLooping Firing）

| 组件 | 版本 | 状态 |
|---|---|---|
| kube-prometheus-stack | 92.16.1 | Prometheus 2/2、Grafana 3/3、其余 1/1，0 重启 |
| Prometheus | v3.15.1 | 保留 6h，约 262 MiB |
| Grafana | 13.3.0 | 约 592 MiB（含 sidecar） |

告警验证：`PodCrashLooping` 由 `crashloop-demo` 触发，约 2 分钟转 Firing，
删除命名空间后恢复 Inactive；`PodNotReady` 已排除已完成 Job Pod 的误报。

访问方式：

```bash
source /d/docker_project/env/env.sh
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# 浏览器打开 http://localhost:3000（本地 POC 已开启匿名只读）
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# 浏览器打开 http://localhost:9090/alerts
```

> quay.io 镜像在本网络极慢，实际安装用 DaoCloud 镜像拉取后
> `docker save --platform linux/amd64` + `kind load image-archive` 导入；
> 步骤见详细报告第 3.2 节。

## Day 5 已完成（2026-11-01）

完成一键复现与本地 CI：`make ci` 通过；删除集群后从零复现并真实下单，最终脚本实测 **190 秒**。

- 完成记录：`notes/day5.md`
- 复现报告：`work/reports/reproduction.md`
- RCA 案例集：`work/reports/rca.md`（8 条）
- 架构与排障路径：`docs/architecture.md`（业务链 / 部署链 / 排障六层）
- 脚本：`work/scripts/`
- CI 工作流：`.github/workflows/ci.yaml`（**已提交文件，未在远端执行**）

常用命令：

```bash
cd /d/docker_project
make ci          # 构建镜像 + 部署 + 冒烟 + 校验
make reproduce   # 从零复现（集群不存在时自动创建）
make verify      # 只校验 Endpoints / Pod / HPA
make smoke       # 只跑真实下单冒烟
```

删除集群后的实测耗时：

| 阶段 | 耗时 |
|---|---:|
| 创建集群 + 节点 Ready | 44 s |
| 导入 13 个镜像 | 78 s |
| metrics-server 就绪 | 34 s |
| Helm 部署 | 25 s |
| 校验 + 冒烟 | 9 s |
| **合计** | **190 s** |

> 190 秒是评审加固后（`load-images.sh` 共用、`verify.sh` 强校验）从零复跑的实测值，
> 日志 `work/logs/day6-postfix-reproduce.log`；首次验收的 209 秒保存在 `work/logs/day5-reproduce.log`。
>
> `frontend-external` 在 Kind 下无法获得外部 IP，已在 values 中关闭；
> 演示统一使用 `kubectl port-forward -n qa-helm svc/frontend 8081:80`。
> 监控栈不计入核心复现；2026-11-01 已按 Day 4 参数另行安装并验证，见 `notes/day6.md`。

## Day 6 已完成（2026-11-01，视频与模拟面试待本人完成）

环境收尾、演示脚本、简历/面试数字和最终校验已完成；`v1.0` tag 已打。

- 完成记录：`notes/day6.md`
- 演示脚本：`notes/demo-script.md`（6 段，约 7 分钟）
- 项目全景：`notes/project-overview.md`

最终状态：11/11 Pod Running、重启 0、11/11 Endpoints 非空、HPA `cpu: 1%/50%`、
无 `<pending>`。`make verify` 与 `make smoke` 均通过。

为录制演示视频，监控栈已按 Day 4 参数补装：`monitoring` 6/6 Pod Ready，
Grafana 13.3.0 正常，3 条告警规则 `health=ok`；日志
`work/logs/day6-monitoring-reinstall.log`。

**未完成（需要本人）**：

- `work/video/day6-demo.mp4` 未录制；
- 10 题模拟面试未执行；
- GitHub Actions 只提交了文件，未在远端运行。
