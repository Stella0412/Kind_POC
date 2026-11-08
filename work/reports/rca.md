# Online Boutique on Kind：RCA 案例集

本文件把 Day 1–4 实际遇到的故障统一为“现象 / 定位命令与输出 / 根因 / 修复 / 验证”五段式。
每条都来自 `work/logs/`、`work/manifests/SOLUTION.md` 或 `notes/dayN.md` 的真实记录，不是事后编写的假设案例。

| # | 故障 | 所属层 | 一句话根因 |
|---|---|---|---|
| RCA-1 | adservice `ImagePullBackOff` | 镜像 | 清单引用了不存在的 tag `v0.3.1` |
| RCA-2 | redis-cart `Pending` | 调度 | `nodeSelector` 指向不存在的节点 |
| RCA-3 | recommendationservice 无法创建 Pod | 准入 | 引用了不存在的 ServiceAccount `boutique` |
| RCA-4 | checkoutservice 无 Endpoints | 服务发现 | Service selector 拼写错误 |
| RCA-5 | 结账支付失败 | 端口 | Service `targetPort` 与容器端口不一致 |
| RCA-6 | 首页货币价格异常 | 配置 | 环境变量里的服务端口写错 |
| RCA-7 | `kind load docker-image` 报 `content digest not found` | 镜像导入 | Docker 29 containerd 存储与 kind 多平台导入不兼容 |
| RCA-8 | adservice 冷启动被 liveness 连续重启 / 100 用户档 OOMKilled | 运行时 | 探针超时过短；内存 limit 300Mi 不足 |

---

## RCA-1：adservice 镜像 tag 不存在

- **现象**：`adservice` Pod 处于 `ImagePullBackOff`，其他服务正常。
- **定位**：

  ```bash
  kubectl describe pod -n qa -l app=adservice | tail -20
  # Failed to pull image ".../adservice:v0.3.1": ... not found
  ```

- **根因**：项目清单引用 `adservice:v0.3.1`，但该版本未发布；adservice 当时的最新稳定 tag 是 `v0.3.4`。
- **修复**：`work/manifests/deploy/adservice.yaml` 与 Helm values 改为 `v0.3.4`。
- **验证**：Pod `Running`，`kubectl get endpoints adservice -n qa-helm` 非空。

## RCA-2：redis-cart 因 nodeSelector 无法调度

- **现象**：`redis-cart` 长时间 `Pending`，事件为 `0/2 nodes are available: 2 node(s) didn't match Pod's node affinity/selector`。
- **定位**：

  ```bash
  kubectl describe pod -n qa -l app=redis-cart | grep -A3 Events
  kubectl get nodes --show-labels | grep kubernetes.io/hostname
  ```

- **根因**：清单写死 `nodeSelector: kubernetes.io/hostname: test-worker-2`，本项目 Kind 集群的 worker 叫 `qa-cluster-worker`。
- **修复**：改为 `qa-cluster-worker`（Helm 的全局 `nodeSelector` 同样固定到 worker）。
- **验证**：Pod 调度成功并 `Ready`；`kubectl get pod -n qa-helm -o wide` 显示位于 worker。

## RCA-3：recommendationservice 因 ServiceAccount 缺失被拒绝创建

- **现象**：Deployment 存在但 Pod 一个都没有；`kubectl get events` 报 `FailedCreate ... serviceaccount "boutique" not found`。
- **定位**：

  ```bash
  kubectl get events -n qa --sort-by=.lastTimestamp | tail
  kubectl get sa -n qa
  ```

- **根因**：清单引用 `serviceAccountName: boutique`，但该命名空间没有创建这个 SA；上游 v0.3.4 使用 `default`。
- **修复**：改为 `serviceAccountName: default`。
- **验证**：Pod 被创建并 `Ready`，recommendationservice Endpoints 非空。

## RCA-4：checkoutservice Service selector 拼写错误导致无 Endpoints

- **现象**：前端可以打开，但结账返回 500；`checkoutservice` 的 Endpoints 为 `<none>`。
- **定位**：

  ```bash
  kubectl get endpoints checkoutservice -n qa
  kubectl get svc checkoutservice -n qa -o yaml | grep -A2 selector
  # app: check-outservice
  kubectl get pods -n qa --show-labels | grep checkout
  # app=checkoutservice
  ```

- **根因**：Service selector 写成了 `check-outservice`，与 Pod 标签 `checkoutservice` 不匹配，Endpoints 控制器找不到后端。
- **修复**：selector 改为 `app: checkoutservice`。
- **验证**：Endpoints 出现 `10.244.1.2:5050`；下单链路恢复。

## RCA-5：paymentservice targetPort 与容器端口不一致

- **现象**：加购正常，提交订单时 checkoutservice 调用支付失败，页面 500。
- **定位**：

  ```bash
  kubectl logs -n qa deploy/checkoutservice | grep -i payment
  kubectl get svc paymentservice -n qa -o yaml | grep -A4 ports
  kubectl get pod -n qa -l app=paymentservice -o yaml | grep -A3 'containerPort\|PORT'
  ```

- **根因**：Service `port: 50051` 但 `targetPort: 50052`，容器实际 `PORT=50051`，流量被转发到未监听端口。
- **修复**：`targetPort` 改为 `50051`。
- **验证**：`POST /cart/checkout` 返回页面包含 “Your order is complete!”。

## RCA-6：frontend 的 CURRENCY_SERVICE_ADDR 端口写错

- **现象**：首页商品价格显示异常，frontend 日志中 currencyservice 调用失败。
- **定位**：

  ```bash
  kubectl logs -n qa deploy/frontend | grep -i currency
  kubectl get svc currencyservice -n qa -o yaml | grep -A4 ports   # 7000
  kubectl get deploy frontend -n qa -o yaml | grep -A2 CURRENCY
  # value: "currencyservice:8000"
  ```

- **根因**：环境变量写成 `currencyservice:8000`，实际 Service/容器监听 `7000`。
- **修复**：改为 `currencyservice:7000`（Helm values 同源）。
- **验证**：首页价格正常，`kubectl logs` 无 currency 报错。

## RCA-7：kind 镜像导入报 content digest not found

- **现象**：`kind load docker-image` 对全部镜像失败：

  ```text
  ctr: rpc error: code = NotFound desc = content digest sha256:bc2bba...: not found
  ```

- **定位**：

  ```bash
  docker save redis:7.4-alpine -o redis.tar
  tar -xOf redis.tar index.json   # 列出 linux/amd64/arm/v6/arm/v7...
  tar -tf redis.tar | grep bc2bba # arm/v6 manifest 不在归档里
  ```

- **根因**：Docker Desktop 29 使用 containerd 镜像存储，`docker save` 写出完整多平台 OCI index，但只打包本机平台 blobs；kind 固定用 `ctr import --all-platforms`，于是引用缺失 manifest 报错。
- **修复**：始终用 `docker save --platform linux/amd64` 导出后 `kind load image-archive`。
- **验证**：`docker exec qa-cluster-worker crictl images | grep -E 'microservices-demo|redis' | wc -l` → 13；Pod 无 ImagePullBackOff。

## RCA-8：探针超时导致冷启动重启，以及 adservice OOMKilled

- **现象**：集群重启后 adservice（Java）和 cartservice 在启动阶段被 liveness 连续重启；100 用户压测档 adservice 出现 `OOMKilled`（exit 137）。
- **定位**：

  ```bash
  kubectl describe pod -n qa-helm -l app=adservice | grep -E 'Restart|OOMKilled|Liveness'
  kubectl get events -n qa-helm --field-selector reason=Unhealthy
  kubectl top pod -n qa-helm | grep adservice
  ```

- **根因**：
  1. kubelet exec 探针默认 `timeoutSeconds: 1`，`grpc_health_probe` 自身还有 1s RPC 超时，Java 冷启动期间必然超时；
  2. adservice 内存 limit 300Mi，在 100 用户档不足。
- **修复**：adservice/cartservice 增加 `startupProbe`（`failureThreshold: 30`），所有 gRPC 探针加 `timeoutSeconds: 5` 与 `-rpc-timeout=5s`；OOM 建议把 limit 提到 512Mi（Day 3 仅记录，未改）。
- **验证**：Helm revision 8 冷启动 0 重启；90 秒 / 100 用户复测 3,814 请求、0 失败。证据见 `work/logs/day3-loadtest-artifacts/rev8-retest/`。

---

## 排障方法总结

1. **先看对象状态**：`kubectl get pods/endpoints`，区分 Pending / ImagePullBackOff / CrashLoopBackOff / Running 但不可用。
2. **再看 Events**：调度、拉镜像、准入错误都在 Events 里，比日志更早出现。
3. **Running ≠ 可用**：必须检查 Readiness、Endpoints 和真实请求。
4. **服务调用失败先查 Service**：selector → Endpoints → targetPort → 容器监听端口 → 环境变量地址。
5. **压测异常先查资源与探针**：`kubectl top`、`OOMKilled`、重启计数、CPU throttling。
