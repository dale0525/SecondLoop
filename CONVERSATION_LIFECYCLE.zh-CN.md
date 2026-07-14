# 对话生命周期

AgentWeave 将对话保存为按 App、agent、tenant、user 和 device 隔离的 session。Desktop Host 使用同一套持久契约恢复历史；移动端 Host 仍可直接调用 Runtime storage API。

## HTTP 契约

所有路由都继承当前 sidecar 的本地传输认证和 Host scope。

| 方法与路径 | 行为 |
| --- | --- |
| `POST /sessions` | 使用经过校验的标题创建 session，并返回完整 session 记录 |
| `GET /sessions?limit=50&cursor=…` | 按最近更新时间列出一个稳定分页 |
| `GET /sessions/{id}` | 加载权威 session、消息和已持久化 runtime events |
| `PATCH /sessions/{id}` | 仅在 `expectedUpdatedAt` 仍匹配时重命名 session |
| `DELETE /sessions/{id}?expectedUpdatedAt=…` | 删除一个未发生变化的 session 及其消息和事件 |
| `GET /sessions/{id}/messages` | 读取经过 scope 隔离的兼容消息历史视图 |
| `POST /sessions/{id}/messages` | 为该 session 串行执行并持久化一个 turn |

标题会去除首尾空白，不能为空或包含控制字符，且最多占用 256 个 UTF-8 字节。分页大小范围为 1～100。未知请求字段、错误时间戳、无效 cursor、不存在的 session 和跨 scope 标识都会按 fail-closed 原则拒绝。

## 分页

Session 分页使用不透明的十六进制 cursor，其中包含 snapshot 时间，以及最后一行的更新时间、创建时间和标识。Storage 查询使用完全一致的确定性排序：

```text
updated_at 降序、created_at 降序、id 升序
```

第一页会固定 snapshot 边界。此后更新的 session 不会移动到当前遍历的后续页，从而避免翻页期间出现重复项；调用方重新开始一次遍历即可取得较新的活动。Cursor 在进入 storage 前会校验格式和大小，本身不授予任何 scope 访问权。

## 乐观并发与 turn 串行化

重命名和删除必须携带调用方最后观察到的 `updated_at`。如果另一个 turn 或 mutation 已经修改 session，Server 返回 `409` 和权威 session 记录。调用方必须刷新，并要求用户重新执行显式操作，不能静默覆盖或删除较新的工作。

在同一个 sidecar 进程内，同一 session 的操作共享私有异步锁。第二个 turn 只有在前一个 turn 提交后才会加载历史。重命名、加载和删除使用同一把锁，因此删除不会与正在执行的模型 turn 竞争；不同 session 仍可独立运行。若数据库在进程协调之外发生变化，SQLite compare-and-swap 条件仍是最终权威。

## Desktop 行为

受管 Desktop 启动时会列出 session，并恢复最近更新的对话。对话抽屉使用真实 Server 数据完成搜索、选择、分页、就地重命名和确认删除。历史列表失败时保留当前对话；遇到 `409` 冲突时刷新权威状态。

浏览器开发通过 Vite 开发代理使用同一套路由契约。Renderer 不会获得受管 sidecar origin 或 transport credential。
