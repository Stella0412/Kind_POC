# Day 0 环境就绪记录

日期：2026-10-31

## 1. 完成项

- [x] 创建根目录 `D:\docker_project`
- [x] 安装 kind v0.33.0、Helm v4.3.1
- [x] 确认 Docker Desktop 可用（29.8.2，Linux 容器）
- [x] 确认 Docker 数据目录已在 D 盘：`D:\DockerData\DockerDesktopWSL`
- [x] 稀疏克隆 DevOps-Projects（仅 project-41）
- [x] 克隆 Online Boutique 源码 v0.3.4
- [x] 验证 Docker Hub 与 gcr.io 拉取
- [x] 编写环境脚本（env.sh / check-env.sh / pull-images.sh）
- [x] 预拉取项目镜像：13/13 全部成功
- [x] 创建 Kind 集群 `qa-cluster`（2 节点 Ready），提前完成 Day 1 第一步
- [x] 生成环境报告 `work/logs/env-report.txt`

## 2. 版本与环境

| 项目 | 值 |
|---|---|
| Docker Desktop | 29.8.2 |
| Docker VM | 7.6 GB RAM / 32 CPU |
| Docker Root Dir | /var/lib/docker（WSL 数据在 `D:\DockerData\DockerDesktopWSL`） |
| Docker Registry Mirrors | `https://hub.rat.dev/`、`https://docker.m.daocloud.io/` |
| kind | v0.33.0 |
| Helm | v4.3.1 |
| kubectl | v1.36.1 |
| Git | 2.55.0 |
| Python | 3.14.7 |
| D 盘剩余 | 约 426 GB |

## 3. 仓库

| 仓库 | 路径 | Commit |
|---|---|---|
| DevOps-Projects（sparse: project-41） | `repos/DevOps-Projects` | `ae6cf63` |
| microservices-demo | `repos/microservices-demo` | `62051a3` (v0.3.4) |

## 4. 网络验证

- `docker pull redis:7.4-alpine`：成功（走 Docker Hub 镜像加速）
- `docker pull gcr.io/.../frontend:v0.3.1`：成功（gcr.io 直连可用）
- 结论：**不需要额外配置 gcr 镜像源**；若后续变慢，再用 `gcr.m.daocloud.io` 拉取后 retag。

## 4.1 镜像预拉结果

13 个镜像全部成功，日志：`work/logs/image-pull-day0.log`。

- adservice 使用 `v0.3.4`（`v0.3.1` 不存在）
- 其余 10 个微服务 + loadgenerator 使用 `v0.3.1`
- 基础镜像：`redis:7.4-alpine`、`busybox:1.36.1`

## 4.2 Kind 集群

已提前创建，Day 1 可直接部署：

```bash
kind create cluster --name qa-cluster --config kind-config/config.yaml
```

结果：

| 节点 | 状态 | 版本 |
|---|---|---|
| qa-cluster-control-plane | Ready | v1.32.2 |
| qa-cluster-worker | Ready | v1.32.2 |

日志：`work/logs/kind-create.log`。

**踩坑记录**：Docker Hub 镜像拉 `kindest/node:v1.32.2` 时 kind 卡住超过 10 分钟。
解决方式是先从 DaoCloud 拉取并 retag：

```bash
docker pull docker.m.daocloud.io/kindest/node:v1.32.2
docker tag docker.m.daocloud.io/kindest/node:v1.32.2 kindest/node:v1.32.2
```

然后再执行 `kind create cluster`，几十秒完成。

## 5. 资源评估

11 个服务 + loadgenerator 的资源请求合计：

- requests：CPU 1.57 核 / 内存 1368 MiB
- limits：CPU 2.83 核 / 内存 2542 MiB

Docker VM 7.6 GB 内存足够，无需调整 Docker Desktop 内存。

## 6. 目录约定

所有工作产物都在 `D:\docker_project`：

```
env\        环境脚本
repos\      源码
work\       manifests / helm / screenshots / video / logs
notes\      每日记录
```

Kubeconfig 固定在 `D:\docker_project\work\kubeconfig`，避免写到 C 盘。

## 7. 已知的 Day 1 修复点

来自仓库 `SOLUTION.md`，需要在部署前先改：

1. `deploy/adservice.yaml`：`adservice:v0.3.1` → `adservice:v0.3.4`（v0.3.1 拉不到）
2. `deploy/redis-cart.yaml`：`nodeSelector: test-worker-2` → `qa-cluster-worker`
3. 其余探针 / Service selector 问题在部署后按事件排查

## 8. 下一步

见 `notes/day1-plan.md`。
