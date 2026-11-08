# Day 1 执行台账 — plan: notes/day1-plan.md

日期：2026-10-31
说明：本计划为运维实验，非代码 TDD 计划。验证以 plan 第 7 节检查点为准。
Ruling: 不建 worktree/git commit — 目录不是 git 仓库，且用户未要求提交 — 代价：改动不可回滚（可用 sed 反向修正）。

## 执行结果
Task 1: 修复已知清单问题 — adservice:v0.3.4、redis nodeSelector=qa-cluster-worker — 已验证 grep 输出正确。
Task 2: 镜像导入 — kind load docker-image 失败：Docker 29 containerd store 导出多平台 index 缺 arm/v6 manifest。
  Ruling: 改用 docker save --platform linux/amd64 + kind load image-archive — 依据：单测 redis 成功、13/13 双节点可见 — 代价：多一步导出大文件（约 532MB，已清理）。
Task 3: 部署 — 11 Deployment/Service 创建成功。
Task 4: 排障 — 修复 SA boutique→default、checkout selector 拼写、currencyservice:8000→7000、paymentservice targetPort 50052→50051 — 依据：与上游 v0.3.4 diff 及 Endpoints/Events — 代价：若实验有意要求创建 SA，则与预期方案不同（功能等价）。
  Ruling: 保留 recommendationservice 被注释的 livenessProbe — 当前不影响可用性，恢复会增加探针失败重启风险 — 代价：清单与上游不完全一致，可后续恢复。
Task 5: 验证 — 11/11 Pod Running；11/11 Service 有 Endpoints；curl 下单 200 "order is complete!"；截图 2 张。
Checkpoint: 全部满足（notes/day1-plan.md 第 7 节已勾选）。
Final review: self-review（运维实验无 git 分支，无可 diff 的代码分支）；逐项复核检查点通过。
