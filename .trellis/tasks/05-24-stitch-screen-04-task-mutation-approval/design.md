# Stitch screen 04 task mutation approval design

## Architecture and Boundaries

- Keep the runtime as the source of truth. The app may render task records,
  recent entity references, approval items, audit refs, and context snapshots
  returned by `RuntimeAgentState`, but it must not infer `上一个待办事项` through
  local natural-language parsing.
- Keep implementation inside the existing Flutter agent UI architecture:
  `AppShell` -> `AgentConversationPage` -> operating message/layout surfaces
  and shared approval components.
- Treat `task_mutation_confirmation` as a first-class task mutation approval
  surface instead of forcing it through the old due-time-only preview.
- Preserve generic approval rendering for other approval kinds. New fields or
  helpers should be reusable for later task mutation variants such as due-date
  changes.
- Do not edit or track Stitch export source files. The local HTML/screenshot
  are evidence only.

## Data Flow and Contracts

1. Runtime state provides the conversation turns:
   - create task request;
   - assistant/task-created response;
   - relative task mutation request;
   - assistant pending-approval response.
2. Runtime state provides the current task record for `整理报销材料`.
3. Runtime state provides a `task_mutation_confirmation` approval item with the
   target task id and proposed record/change data.
4. The UI resolves the current target task from runtime state by id and renders
   the target entity row and pre-approval task preview from that current task.
5. The proposed title is read from approval item record/change data. If it is
   absent, the UI renders an explicit unavailable/degraded value rather than
   inventing a title.
6. Resolver detail, source, audit id, context snapshot, runtime tool, and risk
   label are read from approval item record data, latest context snapshot,
   audit refs, or safe runtime metadata.
7. Approve/reject calls continue through `RuntimeSecretaryAppService`.
8. Edit calls a real approval patch path only when the approval item advertises
   editable title support. Otherwise the UI must expose a disabled/degraded
   edit state.

## Compatibility

- Existing tests for `task_mutation_confirmation` should keep passing, but may
  need expectation updates if the card text becomes more specific.
- Existing due-date mutation behavior must not regress. The new card should
  handle title mutation and due-date mutation distinctly, or use a generic diff
  model that can represent both.
- Runtime payload variants should be handled defensively: snake_case and
  camelCase fields may both appear in raw records.
- Managed pro and self-managed should share the same visual/task mutation
  surface because the user-facing capability contract is the same.

## Tradeoffs

- Prefer a typed or centralized extractor for task mutation approval display
  data over scattered raw-map casts in widgets. This reduces the chance that
  screen 05+ repeats the same parsing differently.
- Keep server changes out of scope unless the current runtime contract cannot
  provide or safely degrade a required field. UI can render unavailable
  metadata honestly, but it cannot claim a real mutation landed without runtime
  evidence.
- The Stitch screen is labelled "Action Center" with the Tasks nav active. The
  local mapping stays in the current agent operating shell unless the existing
  app already exposes a formal action-center route; avoid broad navigation
  rewrites for this child.

## Rollback and Operational Notes

- Most changes should be reversible by reverting focused Flutter UI/test files.
- If a server contract gap is discovered, stop and record the required
  `SecondLoopServer` change before declaring screen 04 complete.
- Preserve the canonical screen sequence and parent task mapping so screen 05
  can continue from a clean, independently verified child task.
