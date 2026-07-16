---
name: secondloop-routines
description: Use for a source-backed daily brief, follow-up review, commitment check, meeting preparation, workspace connection, reminder, or concise personal secretary action list. 适用于有来源的每日简报、跟进复盘、承诺检查、会议准备、工作区连接、提醒和私人秘书行动清单。
aliases:
  - 每日简报
  - 跟进复盘
  - 承诺检查
  - 会议准备
  - 连接工作区
  - 提醒
---

# SecondLoop Routines

Build every brief from authoritative results that are available in the current App scope. Mail, Memory, Tasks, Calendar, Scheduler, and Action records may be cited; model inference is context, never a replacement for a missing source.

For a daily brief, order the result as:

1. confirmed deadlines, blocked people, and time-sensitive risks;
2. messages that require a reply or decision;
3. approved actions waiting to run or reconcile;
4. commitments that the user has explicitly made;
5. optional context that can safely wait.

For follow-up review, separate confirmed commitments from plausible suggestions. Include source identity, date, owner, and current state whenever the provider returns them.

For meeting preparation, summarize participants and recent context only from resolved contacts, authoritative calendar records, Mail threads, or committed Memory. Mark missing context instead of inventing it.

Keep the result short. Name the next action and owner. Never turn a suggestion into a durable task, reminder, or outbound message without the required user confirmation and Runtime approval.

## Use chat cards for confirmation

Keep the standard AgentWeave conversation as the only workspace. Use `structured_content_publish` when a connection or reminder needs a clear preview, confirmation, or durable status. Use `application/vnd.agentweave.card+json` for reminder cards and the supported A2UI MIME for connection cards. Put only display text, fields, status, and action labels in the public payload.

Put trusted action parameters only in an opaque binding. Give every binding a stable idempotency key, an expiry no more than 24 hours away, an empty fail-closed input schema unless user input is truly required, and constraints that exactly match the authorized provider, connectors, and capabilities. Never put an authorization URL, OAuth state, code, token, client secret, password, or credential in card content.

For Google Workspace authorization, use provider `google-workspace`, connectors `agentweave-mail`, `agentweave-calendar`, and `agentweave-contacts`, and capabilities `mail`, `calendar`, and `contacts`. For Microsoft mail authorization, use provider `microsoft-graph`, connector `agentweave-mail`, and capability `mail`. For Microsoft calendar and contacts authorization, use provider `microsoft-graph`, connectors `agentweave-calendar` and `agentweave-contacts`, and capabilities `calendar` and `contacts`. Ask which provider or capability the user wants before publishing the action. Use the `oauth.start` intent; the Host opens the browser and writes the callback result into the next card revision.

For a reminder, first resolve the exact local time, timezone, recurrence, notification title, notification body, and misfire policy. Publish a preview card with a `schedule.create` binding. Its private parameters must contain the Scheduler request and a declarative notification payload without App, tenant, or user scope. Treat the notification `dedupeKey` as a stable seed; the Host derives one delivery identity per durable scheduler run. Do not call `schedule_create` before the user accepts the preview card.

After a trusted action succeeds, rely on the Host-published next revision for authoritative status, schedule ID, timezone, next run, misfire policy, or connected account. Do not invent a success message while the card still reports a pending or failed state.
