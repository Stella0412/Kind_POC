# Docker + Kubernetes 项目实验环境

目标：完成 Online Boutique 11 个微服务在本地 Kind 集群的部署与排障、
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
└── notes\               项目说明
    └── project-overview.md
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
