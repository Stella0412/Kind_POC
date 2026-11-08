# Day 6 完成记录：演示、面试与收尾

日期：2026-11-01
状态：**部分完成** —— 环境收尾、演示脚本、简历/面试数字、最终校验、tag 已完成；
**演示视频录制与模拟面试需要本人完成**，未执行。

## 1. 环境收尾（6.1）

- 复现使用全新集群，`qa` 对照命名空间不存在；无需额外删除。
- `frontendExternal.enabled` 已改为 `false`，Kind 下不再出现 `<pending>` 的 LoadBalancer。
- 最终状态（2026-11-01）：

| 项 | 结果 |
|---|---|
| 节点 | 2/2 Ready（v1.32.2） |
| Pod | 11/11 `Running 1/1`，重启数 **0** |
| Service | 11/11 Endpoints 非空，无 `<pending>` |
| HPA | `frontend`，`cpu: 1%/50%`，min 1 / max 4 |
| Helm | `online-boutique` revision 1，`deployed` |
| 监控 | `monitoring` 6/6 Pod Running（Grafana 3/3、Prometheus 2/2、node-exporter 2/2），0 重启 |
| 告警规则 | `online-boutique.rules` 3 条 `health=ok`，当前 inactive |

证据：

- `work/logs/day6-final-nodes.log`
- `work/logs/day6-final-pods.log`
- `work/logs/day6-final-svc.log`
- `work/logs/day6-final-hpa.log`
- `work/logs/day6-final-helm.log`
- `work/logs/day6-final-endpoints.log`
- `work/logs/day6-final-restarts.log`
- `work/logs/day6-monitoring-reinstall.log`（监控补装、规则校验、Prometheus 采样）
- `work/logs/day6-demo-loadtest.log`（演示压测：4,057 请求、0 失败、34.04 RPS）

### 1.1 监控补装与演示压测（2026-11-01）

- Helm release `monitoring` revision 1，chart 92.16.1，values 与 Day 4 相同；
  补拉 `node-exporter:v1.12.1-distroless` 与 `kube-webhook-certgen:1.11.0` 后导入 Kind。
- 6/6 Pod Ready，0 重启；Grafana 13.3.0 `/api/health` 返回 `database: ok`。
- Prometheus 中 `online-boutique.rules` 三条规则 `health=ok`、`state=inactive`。
- 演示压测（50 用户 / 2 分钟）：**4,057 请求、0 失败、34.04 RPS**；
  HPA 扩到 4 个副本（压测前为 1，watch 首次采样已是 3）；
  Prometheus 已采集 `qa-helm` 的 42 条容器 CPU 序列。
- 压测 Job 已删除，命名空间恢复为 11 个业务 Pod；Prometheus 保留 6h，
  超过 6h 再录需重跑：先 `kubectl apply -f work/manifests/loadtest/configmap.yaml`，
  再 `kubectl apply -f work/manifests/loadtest/job-demo.yaml`。

## 2. 演示脚本（6.2）

- [x] `notes/demo-script.md`：6 段、约 7 分钟，含逐段画面、口播稿和录制前检查。
- [ ] `work/video/day6-demo.mp4`：**未录制**（需要本人出镜/口播）。
- [ ] 录制后自检（可播放、无敏感信息、数字与报告一致）：**未执行**。

## 3. 简历与面试材料（6.3）

- [x] `notes/project-overview.md`：状态更新为 Day 0–6；效果表替换为真实数字；
      修正“frontend / currencyservice 镜像”为只做了 frontend，55.9 MB → 52.8 MB。
- [x] `notes/interview-qa.md`：30 秒介绍中的 `X/Y/Z` 占位符替换为 20/50/100 三档真实数据，
      补充 HPA 93 秒和 190 秒复现。
- [x] `notes/resume-bullets.md`：6 条简历条目 + 30 秒 / 3 分钟 / 10 分钟自我介绍 + 数字速查表。
- [x] 所有对外数字均可追溯到 `work/logs/` 或 `work/reports/`。
- [x] 明确标注未执行项：GitHub Actions 远端运行、演示视频、模拟面试。

## 4. 模拟面试与最终校验（6.4）

- [ ] 10 题限时模拟面试：**未执行**（需要本人录音/口述）。
      执行稿已整理：`notes/mock-interview-p0.md`（10 题 + 收尾题、每题 2 分钟、评分表、红线清单）；
      原 25 题题库 `notes/interview-qa-quiz.md` 完整保留。
- [x] `make verify`：`VERIFY OK: nodes Ready, 11 pods Running/Ready, HPA frontend, all services have endpoints`
- [x] `make smoke`：`SMOKE OK: homepage / product / cart / checkout`
- [x] 工作区无未提交改动（提交后确认）
- [x] Git tag `v1.0`

完整日志：`work/logs/day6-final-verify.log`、`work/logs/day6-final-smoke.log`。

## 5. 最终清单

- [x] 11/11 Pod Running，Endpoints 非空
- [x] 下单链路可演示
- [x] HPA 扩容有日志/报告（Day 3）
- [x] Grafana 已按 Day 4 参数重装并验证（Day 4 截图 + 本次监控日志）
- [x] 6 类故障 RCA（共 8 条）
- [x] 30 分钟复现有计时和日志（最终脚本 190 秒）
- [ ] 演示视频可播放
- [x] 简历/面试数字全部可追溯
- [x] README 能让新人独立复现

## 6. 未完成 / 明确声明

1. **演示视频未录制**：`work/video/day6-demo.mp4` 不存在；`notes/demo-script.md` 已可直接照读。
2. **模拟面试未执行**：10 题自测需要本人完成，不能由文档代替。
3. **监控栈已补装（为演示视频）**：2026-11-01 19:14 按 Day 4 的
   `work/manifests/monitoring/values.yaml` 重装，补拉了 node-exporter 与
   kube-webhook-certgen；6/6 Pod Ready，Grafana `/api/health` 正常，3 条规则
   `health=ok`。监控仍不计入 190 秒核心复现。日志
   `work/logs/day6-monitoring-reinstall.log`。
4. **GitHub Actions 未在远端执行**：只提交了工作流文件。
5. **Day 5 复现截图未生成**：以 `work/logs/day5-reproduce-*.log` 文本输出作为证据；
   终端截图可由本人在本地补齐。
