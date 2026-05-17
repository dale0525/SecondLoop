# Implementation Plan Notes

日期：2026-05-17

本目录不再保留从 `.tmp/docs` 直接迁入的超长 implementation plan。当前仓库约束要求单文件超过 1000 行时必须重构，而这些旧计划已经被拆分后的架构文档取代。

当前实施应以这些文档为准：

- `docs/architecture/agent-state-store-secretary-memory.md`
- `docs/architecture/conversation-context-action-guardrail.md`
- `docs/architecture/skill-runtime-architecture.md`
- `docs/qa/managed-pro-manual-qa.md`

当前可执行计划：

- `docs/superpowers/plans/2026-05-17-skill-runtime-phase-1-implementation-plan.md`：实现 skill manifest/catalog、`web-research` skill package、runtime tool request enforcement、managed pro 部署绑定和 QA-CHAT-05 验证。
- `docs/superpowers/plans/2026-05-17-client-dart-http-runtime-implementation-plan.md`：把主客户端收敛为 Flutter/Dart + HTTP runtime client，保留离线纯文本笔记编辑、附件列表/预览/清理，并移除主 App Rust runtime 依赖。

执行状态：

- client Dart HTTP runtime 计划已落地 note HTTP contract、离线纯文本 note draft/outbox、附件 cloud inventory/preview/delete/cache cleanup、runtime-first product navigation guard，以及新 runtime-client 路径的 Rust dependency guard。
- 完整物理删除主客户端 Rust 仍需单独拆分后续计划：当前 backend、chat/settings/legacy attachments、`pubspec.yaml`、platform plugin 和 web build 链仍依赖 FRB/Rust。后续删除必须先把这些路径迁到 Dart/runtime interface，再从主 App dependency graph 移除 Rust；self-managed deploy helper 可保留自己的独立 Rust 实现。

历史计划处理：

- 当前分支 `.tmp/docs/superpowers/plans/2026-05-16-agent-state-store-secretary-memory-implementation-plan.md` 未迁入正文；其有效目标已沉淀到 Agent State Store 架构文档。
- 当前分支 `.tmp/docs/superpowers/plans/2026-05-16-conversation-context-action-guardrail-implementation-plan.md` 未迁入正文；其有效目标已沉淀到 Conversation Context Guardrail 架构文档和 QA checklist。
- 主分支 `.tmp/docs/superpowers/plans/2026-05-10-runtime-first-secretary-mvp-implementation-plan.md` 未迁入正文；它是更早的 monolithic plan，已被 2026-05-16/17 的拆分设计替代。

后续如果需要执行具体实现，应基于当前架构文档重新生成短小、分阶段、可验证的计划，而不是继续引用旧的长计划。
