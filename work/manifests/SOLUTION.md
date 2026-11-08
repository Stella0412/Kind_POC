# Day 1 排障记录：Online Boutique on Kind

日期：2026-10-31
集群：`qa-cluster`（kind v0.33.0，k8s v1.32.2，control-plane + worker）
命名空间：`qa`
最终状态：**11/11 Pod Running & Ready，所有 Service Endpoints 就绪，前端下单链路验证通过**

---

## 0. 问题汇总

| # | 现象 | 根因 | 修复文件 |
|---|---|---|---|
| 1 | `kind load docker-image` 全部失败：`content digest sha256:... not found` | Docker 29 使用 containerd 镜像存储，`docker save` 导出多平台 OCI index，但只打包本机平台 blobs；kind 的 `ctr import --all-platforms` 找不到 arm/v6 等 manifest | 不改清单，改导入方式（见 §1） |
| 2 | `adservice` ImagePullBackOff | 清单引用不存在的 `adservice:v0.3.1` | `deploy/adservice.yaml` |
| 3 | `redis-cart` Pending | `nodeSelector` 指向不存在的 `test-worker-2` | `deploy/redis-cart.yaml` |
| 4 | `recommendationservice` 无法创建 Pod：`serviceaccount "boutique" not found` | 引用了命名空间中不存在的 ServiceAccount | `deploy/recommendationservice.yaml` |
| 5 | `checkoutservice` Service 无 Endpoints，下单 500 | Service selector 拼写为 `check-outservice`，与 Pod 标签 `checkoutservice` 不匹配 | `deploy/checkoutservice.yaml` |
| 6 | 页面货币价格异常 / 货币服务调用失败 | `CURRENCY_SERVICE_ADDR=currencyservice:8000`，实际监听 7000 | `deploy/frontend.yaml` |
| 7 | 结账时支付调用失败 | Service `targetPort: 50052`，容器实际监听 50051 | `deploy/paymentservice.yaml` |

> 说明：adservice 启动初期出现过 1~2 次探针 1s 超时（Java 服务冷启动），随后自行恢复 Ready，无需修改探针参数。

---

## 1. 镜像导入：kind + Docker 29 的兼容问题

### 现象

```text
ERROR: failed to load image: command "docker exec --privileged -i qa-cluster-control-plane
ctr --namespace=k8s.io images import --all-platforms --digests --snapshotter=overlayfs -"
failed: ctr: rpc error: code = NotFound desc = content digest sha256:bc2bba...: not found
```

### 定位过程

```bash
docker save redis:7.4-alpine -o redis.tar
tar -xOf redis.tar index.json
# index.json 里列出了 linux/amd64、linux/arm/v6、linux/arm/v7 ...
tar -tf redis.tar | grep bc2bba   # MISSING：arm/v6 manifest 不在归档里
```

Docker 29 的 containerd image store 在 `docker save` 时写出完整多平台 index，但只包含本机平台的 blobs。kind 固定用 `--all-platforms` 导入，于是引用缺失 manifest 报错。

### 解决方案

```bash
# 只导出当前平台，index 中不再引用其他平台
docker save --platform linux/amd64 \
  <所有镜像...> -o all-images-amd64.tar

kind load image-archive all-images-amd64.tar --name qa-cluster

# 验证
docker exec qa-cluster-worker crictl images | grep -E 'microservices-demo|redis|busybox' | wc -l
# 13
```

结果：13 个镜像在 control-plane 与 worker 均为 13/13。

---

## 2. 部署顺序

```bash
source /d/docker_project/env/env.sh
cd /d/docker_project/repos/DevOps-Projects/project-41-online-boutique-microservices

kubectl create namespace qa
kubectl apply -n qa -f deploy/
kubectl get pods -n qa -w
```

---

## 3. 逐个问题排查

### 3.1 recommendationservice：ServiceAccount 不存在

```bash
kubectl get events -n qa --sort-by=.lastTimestamp | tail
# FailedCreate ... serviceaccount "boutique" not found
```

对比上游 `repos/microservices-demo/kubernetes-manifests/recommendationservice.yaml`，上游使用 `default`。
修复：

```yaml
spec:
  serviceAccountName: default   # 原 boutique
```

重新 apply 后 Pod 正常创建并 Ready。

### 3.2 checkoutservice：Service selector 拼写错误

```bash
kubectl get endpoints -n qa
# checkoutservice   <none>
kubectl get svc checkoutservice -n qa -o yaml | grep -A2 selector
# app: check-outservice
kubectl get pods -n qa --show-labels | grep checkout
# app=checkoutservice
```

修复 selector 为 `app: checkoutservice`，Endpoints 变为 `10.244.1.2:5050`。

### 3.3 frontend：货币服务端口错误

```yaml
# deploy/frontend.yaml
- name: CURRENCY_SERVICE_ADDR
  value: "currencyservice:8000"   # 实际 currencyservice 监听 7000
```

修复为 `currencyservice:7000`。验证：首页价格正常显示（USD 换算依赖 currencyservice）。

### 3.4 paymentservice：Service targetPort 错误

```yaml
# deploy/paymentservice.yaml
ports:
- name: grpc
  port: 50051
  targetPort: 50052   # 容器 PORT=50051
```

修复为 `targetPort: 50051`。验证：结账返回 `order is complete!`。

### 3.5 adservice / redis-cart（部署前已修）

```bash
sed -i 's|adservice:v0.3.1|adservice:v0.3.4|' deploy/adservice.yaml
sed -i 's|test-worker-2|qa-cluster-worker|' deploy/redis-cart.yaml
```

---

## 4. 验证证据

### 4.1 集群与 Pod

见 `work/logs/day1-cluster-state.log`：

- 2 个节点 Ready（v1.32.2）
- 11 个 Pod 全部 `1/1 Running`
- 11 个 Service 均有 Endpoints

### 4.2 前端下单链路（curl 实测）

```text
GET  /                    → 200
POST /cart (加购)         → 302 → /cart
GET  /cart                → 200，购物车包含 OLJCESPC7Z
POST /cart/checkout       → 200，页面含 "order is complete!"
```

订单号示例：`e2b11f6b-d525-11f1-82d2-86c94a4e3273`

### 4.3 截图

- `work/screenshots/day1-frontend-home.png`
- `work/screenshots/day1-frontend-product.png`

---

## 5. 复核命令

```bash
source /d/docker_project/env/env.sh
kubectl get nodes
kubectl get pods -n qa -o wide
kubectl get endpoints -n qa
kubectl port-forward -n qa svc/frontend 8080:80
# 浏览器打开 http://localhost:8080
```
