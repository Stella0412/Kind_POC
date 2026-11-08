# Day 1 完成记录：部署 + 第一轮排障

日期：2026-10-31
状态：**已完成**（11/11 Pod Running，前端下单链路验证通过）

## 1. 完成项

- [x] 修复已知清单问题（adservice 镜像版本、redis-cart nodeSelector）
- [x] 解决 kind + Docker 29 镜像导入失败（`content digest not found`）
- [x] 13 个镜像成功加载到 control-plane 与 worker
- [x] 在 `qa` 命名空间部署 11 个微服务
- [x] 排查并修复 4 个运行时问题（SA、Service selector、货币端口、支付 targetPort）
- [x] 11 个 Pod 全部 `1/1 Running`，所有 Service 有 Endpoints
- [x] 前端页面与完整下单链路验证通过（curl + 截图）
- [x] 排障记录写入 `work/manifests/SOLUTION.md`
- [x] 修复后的清单归档到 `work/manifests/deploy/`

## 2. Day 1 检查点

- [x] 集群 2 个节点 Ready
- [x] 至少 9 个 Pod Running —— 实际 11/11
- [x] 每个未 Running 的 Pod 都有 Event 记录 —— 已记录并修复
- [x] 截图保存到 `work/screenshots/`
- [x] 排障过程写入 `work/manifests/SOLUTION.md`

## 3. 修复清单（与上游 v0.3.4 对比）

| 文件 | 问题 | 修复 |
|---|---|---|
| adservice.yaml | 镜像 `v0.3.1` 不存在 | → `v0.3.4` |
| redis-cart.yaml | nodeSelector `test-worker-2` | → `qa-cluster-worker` |
| recommendationservice.yaml | SA `boutique` 不存在 | → `default` |
| checkoutservice.yaml | Service selector `check-outservice` | → `checkoutservice` |
| frontend.yaml | `CURRENCY_SERVICE_ADDR` 端口 8000 | → 7000 |
| paymentservice.yaml | Service `targetPort` 50052 | → 50051 |

## 4. 关键排障：kind 镜像导入

Docker Desktop 29 使用 containerd 镜像存储，`docker save` 会导出多平台 OCI index 但只打包本机平台 blobs，
kind 的 `ctr import --all-platforms` 因此报 `content digest ... not found`。

解决：

```bash
docker save --platform linux/amd64 <images...> -o all-images-amd64.tar
kind load image-archive all-images-amd64.tar --name qa-cluster
```

## 5. 验证证据

- 集群状态：`work/logs/day1-cluster-state.log`
- 排障全文：`work/manifests/SOLUTION.md`
- 截图：`work/screenshots/day1-frontend-home.png`、`day1-frontend-product.png`
- 下单实测：GET / → 200；POST /cart → 302；GET /cart → 200；POST /cart/checkout → 200（"order is complete!"）

## 6. 环境访问

```bash
source /d/docker_project/env/env.sh
kubectl port-forward -n qa svc/frontend 8080:80
# http://localhost:8080
```

## 7. 下一步（Day 2 建议）

- 用 `microservices-demo` 源码构建至少一个自有镜像（如 frontend），替换 gcr 镜像验证
- 将 `deploy/` 封装为 Helm Chart（values 覆盖镜像 tag、资源、副本数）
- 补充 loadgenerator（`test/loadgenerator.yaml`）跑一轮压测并留存输出
- 整理 Day 2 计划到 `notes/day2-plan.md`
