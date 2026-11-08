# 架构与排障路径

本项目是 Online Boutique（11 个微服务）在单机 Kind 集群上的 POC。
本文回答三个问题：**业务怎么调用、镜像怎么进集群、出问题按什么顺序查**。

- 集群：`qa-cluster`（Kind v0.33.0，Kubernetes v1.32.2，control-plane + worker）
- 命名空间：`qa-helm`（Helm release `online-boutique`）
- 入口：`kubectl port-forward -n qa-helm svc/frontend 8081:80`

## 1. 业务调用链

```mermaid
graph LR
    U[Browser] -->|HTTP :80| F[frontend]
    F -->|gRPC 3550| PC[productcatalogservice]
    F -->|gRPC 7000| CU[currencyservice]
    F -->|gRPC 7070| CA[cartservice]
    F -->|gRPC 8080| RE[recommendationservice]
    F -->|gRPC 9555| AD[adservice]
    F -->|gRPC 50051| SH[shippingservice]
    F -->|gRPC 5050| CO[checkoutservice]

    CO -->|gRPC 5050 / 3550 / 50051 / 5000 / 7000 / 7070| CO2[checkout 编排]
    CO2 --> PAY[paymentservice 50051]
    CO2 --> MAIL[emailservice 5000]
    CO2 --> SH
    CO2 --> CA
    CO2 --> PC
    CO2 --> CU

    CA -->|Redis 6379| R[(redis-cart)]
```

关键点：

- 只有 frontend 暴露 HTTP；其余服务都是集群内 gRPC。
- checkoutservice 是编排者：一次下单会串行/并行调用支付、邮件、物流、购物车、商品、货币六个服务，因此它是下单链路最脆弱的一环。
- cartservice 的有状态依赖只有 redis-cart；当前 POC 用 `emptyDir`，节点/Pod 重建会丢购物车。

## 2. 部署链路

```mermaid
graph TB
    SRC[repos/microservices-demo/src/frontend] --> PREP[prepare-context.sh<br/>复制源码 + 打 metadata 探测补丁]
    PREP --> BUILD[docker build<br/>Dockerfile.day2 多阶段]
    BUILD --> IMG[local/frontend:day2]
    IMG --> SAVE[docker save --platform linux/amd64]
    SAVE --> LOAD[kind load image-archive]
    LOAD --> CTR[control-plane + worker 的 containerd]
    CTR --> POD

    CHART[work/helm/online-boutique<br/>values.yaml + templates] --> HELM[helm upgrade --install]
    HELM --> DEP[Deployment<br/>启动探针/就绪/存活]
    HELM --> SVC[Service]
    HELM --> HPA[HorizontalPodAutoscaler]
    DEP --> POD[Pod]
    POD --> EP[Endpoints]
    SVC --> EP
    EP --> DNS[CoreDNS<br/>服务名解析]
    DNS --> PF[kubectl port-forward<br/>本地访问]
```

关键点：

- `repos/` 是上游源码，不修改；所有定制（补丁、Dockerfile、Chart、脚本）都在 `work/`。
- Docker 29 的 containerd 镜像存储必须用 `docker save --platform linux/amd64`，否则 kind 导入报 `content digest not found`（见 RCA-7）。
- `kind load` 不会覆盖节点上已存在的同名 tag；重建镜像后需要 `kubectl rollout restart`。
- HPA 开启时 Deployment 不设置 `replicas`，副本数由 HPA 管理；metrics-server 在 Kind 下必须加 `--kubelet-insecure-tls`。

## 3. 排障六层

从外到内，逐层排除；每层先看状态，再看 Events，最后看日志。

```mermaid
graph TB
    A[请求失败] --> L1[1 调度层<br/>Pod Pending?]
    L1 -->|是| C1[kubectl describe pod<br/>nodeSelector / 资源 / 污点]
    L1 -->|否| L2[2 镜像层<br/>ImagePullBackOff?]
    L2 -->|是| C2[检查 tag 是否存在<br/>docker save / kind load 路径]
    L2 -->|否| L3[3 准入层<br/>Pod 没有被创建?]
    L3 -->|是| C3[kubectl get events<br/>ServiceAccount / Quota / Webhook]
    L3 -->|否| L4[4 服务发现层<br/>Endpoints 为空?]
    L4 -->|是| C4[selector 与 Pod 标签是否一致]
    L4 -->|否| L5[5 端口层<br/>连接被拒绝/超时?]
    L5 -->|是| C5[Service port / targetPort<br/>containerPort / 监听地址]
    L5 -->|否| L6[6 配置层<br/>Running 但功能异常?]
    L6 --> C6[环境变量地址与端口<br/>日志中的下游调用错误]
```

| 层 | 典型症状 | 第一命令 | 本项目案例 |
|---|---|---|---|
| 调度 | Pod Pending | `kubectl describe pod` | RCA-2 nodeSelector |
| 镜像 | ImagePullBackOff | `kubectl describe pod` | RCA-1 tag 不存在 |
| 准入 | Deployment 无 Pod | `kubectl get events` | RCA-3 ServiceAccount |
| 服务发现 | Service 无 Endpoints | `kubectl get endpoints` | RCA-4 selector 拼写 |
| 端口 | 连接拒绝/超时 | `kubectl get svc -o yaml` | RCA-5 targetPort |
| 配置 | Running 但业务 500 | `kubectl logs` + 环境变量 | RCA-6 货币端口 |

补充：**Pod Running 不等于服务可用**。必须同时满足 Readiness 通过、Endpoints 非空、真实请求成功。
完整案例见 `work/reports/rca.md`。
