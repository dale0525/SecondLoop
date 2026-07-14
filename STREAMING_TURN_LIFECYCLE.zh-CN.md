# 流式 Turn 生命周期

AgentWeave Desktop 使用可持久化、基于游标的事件流来运行耗时对话。事件流通过可信 Electron IPC 传输，因此 Renderer 不会接触 sidecar 传输凭据或已保存的模型 API Key。

## 契约

`POST /sessions/{session_id}/turns` 接收有界的 `content` 字符串和调用方生成的 `requestId`。`(session_id, requestId)` 组合具有幂等性。新请求成功时返回 `202 Accepted`；完全相同的重放会返回已有 turn，不会再次写入用户消息。

Runtime 会在模型执行开始前，通过同一个事务创建 turn 账本记录和用户消息。每个会话最多只有一个 `running` turn。持久 turn ID 也会传入 Runtime，因此 `turn_started`、终态事件、事件记录、取消和重放都引用同一个身份。

`GET /sessions/{session_id}/turns/{turn_id}/events` 返回 `after` 游标之后的事件。响应包含下一个事件序号、权威 turn 状态和 `hasMore`。`waitMs` 提供最长 25 秒的有界长轮询。客户端重连时携带最后一个已经成功渲染的游标，并按事件 ID 去重。

`POST /sessions/{session_id}/turns/{turn_id}/cancel` 请求取消当前执行。取消会在 Server task 的安全边界生效，并产生唯一、持久化的 `turn_cancelled` 终态事件。turn 已进入终态后再次取消不会产生副作用。

## 持久状态

- `running`：执行仍可发布事件。
- `completed`：终态事件和 assistant 消息已在同一事务中提交。
- `failed`：执行在持久失败边界结束。
- `cancelled`：用户请求了安全停止。
- `interrupted`：进程恢复时发现 turn 仍处于 `running`。

非终态事件必须先持久化，之后才可被客户端重放。正常完成时，assistant 消息、终态事件、turn 状态和会话时间戳在同一事务中提交。turn 进入终态后，迟到事件会被拒绝。

## 恢复

Storage 启动时，遗留的所有 `running` turn 都会转为 `interrupted`，并写入一条带稳定重启说明的 `turn_failed` 事件。此前已经保存的增量仍可重放。Desktop 会保留已经渲染的部分回复，请求 sidecar supervisor 恢复，然后从最后一个事件游标继续。如果 sidecar 已经重启，首次重放会返回权威的 `interrupted` 终态，而不会静默丢失请求。

加载会话时会同时返回消息、Runtime 事件和 turn 账本记录。因此新的 Renderer 可以在窗口重载后恢复仍在运行的 turn，也可以在 sidecar 重启后解释中断状态。

## 兼容性与限制

为兼容已有集成，同步接口 `POST /sessions/{session_id}/messages` 仍然保留。新的 Desktop 对话流程使用持久 turn 接口。事件页最多返回 100 条记录，request ID 最长 128 个可移植字符，请求正文最大为 1 MiB。

事件流按 App、agent、tenant、user、device、session 和 turn 共同隔离。Electron 只暴露启动 turn、重放事件和取消这三类固定操作，Renderer 仍不能请求任意 URL。
