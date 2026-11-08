# Day 2 执行台账 — plan: notes/day2-plan.md

日期：2026-10-31
说明：运维/交付实验，非代码 TDD 计划。验证以各节“验收”条件与实际证据为准。
Ruling: 不建 worktree、不 git commit — 目录不是 git 仓库，用户未要求提交 — 代价：改动不可回滚（可重建镜像/重装 release）。

## 执行结果

Task 1: 自建镜像 — `local/frontend:day2` 多阶段构建成功，52.8 MB（gcr 基线 55.9 MB）。
  Ruling: 弃用 `golang:1.15-alpine`，改用 `alpine:latest` + `apk add go`（Go 1.26.10） — 依据：官方基础镜像下载约 15 KB/s，40+ 分钟未完成；Alpine 仓库可用且编译通过 — 代价：工具链版本高于上游，若上游代码依赖 1.15 特性差异需回退（已用运行验证覆盖）。
  Ruling: `sed` 补丁产生非法 Go 代码，改为 Python 精确字符串替换并在 `prepare-context.sh` 中固化 — 依据：sed 对 `&&` 的转义导致 handlers.go:97 语法错误 — 代价：脚本依赖上游代码块原文，升级上游时需同步更新。

Task 2: 首页 4s 延迟 — 根因为 `metadata.google.internal.` DNS 探测（CoreDNS SERVFAIL + resolver 重试），应用层加 `DISABLE_METADATA_DETECTION` 开关后中位延迟 4000ms → 19ms。
  Ruling: 不对集群 CoreDNS 做修改 — 该集群级变更被权限校验拒绝，未绕过；改为应用层开关 — 代价：交付物与上游 frontend 源码存在差异，需维护补丁。
  Ruling: 首版补丁条件 `len(addrs) >= 0` 恒真，修正为 `> 0` — 依据：平台标识仍显示 Google Cloud — 代价：需重新构建镜像（已重建并验证显示 `local`）。

Task 3: 镜像导入 — `kind load image-archive` 不替换节点上已存在的同名 tag。
  Ruling: 使用 `kubectl rollout restart deploy/frontend` 强制重新调度，而非另建新 tag — 依据：节点 tag 已指向新 digest，但 Pod 仍在旧容器上；重启后 imageID 与节点一致 — 代价：同名 tag 的可变性在正式环境有歧义，生产应使用不可变 tag。

Task 4: Helm Chart — lint/template/install/upgrade/rollback/history 全部通过；revision 5 deployed；11 Deployment + 12 Service。
  Ruling: `qa` 与 `qa-helm` 并存 — 依据：保留 Day 1 基线便于对比 — 代价：占双份资源（本地 7.6GB 内存下仍可运行）。

Task 5: 压测 — 10 并发 / 5 分钟，最终版 666 请求、0 失败、2.23 RPS、中位 19ms、P95 85ms；基线 561 请求、1.88 RPS、中位 4000ms。
  验收：失败率 0% ≤ 1% — 通过。

Task 6: 交付物 — `notes/day2.md`、`work/reports/day2-loadtest.md`、截图（平台标识 `local`）、日志归档。

Final review: self-review（无 git 分支可 diff）；复核检查点：Helm 11/11 Running、12/12 Endpoints、压测 0 失败、截图与日志齐全。
