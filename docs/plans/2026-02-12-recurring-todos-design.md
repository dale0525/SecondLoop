# Recurring Todos Design

Date: 2026-02-12
Status: Draft (validated)

## Summary
Add recurring todo support with a "series + occurrence" model. Each recurrence has a TodoSeries that stores the recurrence rule. Each scheduled instance is a Todo occurrence linked to the series. When an occurrence is completed, the app spawns the next occurrence (idempotent) and preserves history.

This design intentionally does not provide backward-compatible migration for existing todo data.

## Goals
- Create recurring todos via UI and semantic parsing (local + cloud).
- Preserve a history of completed occurrences.
- Spawn the next occurrence only when the current occurrence is completed.
- Support editing scope: "this occurrence", "this and future", "entire series".
- Multi-language semantic parsing for recurrence phrases.

## Non-goals (v1)
- Pre-generating future occurrences.
- Calendar event export / ICS.
- Complex RRULE parity (e.g., BYSETPOS, exceptions, holidays).

## Key Decisions
- Data model: TodoSeries (rule) + Todo (occurrence).
- Recurrence encoding: structured rule object (freq/interval/by_weekdays/by_month_day/time_local/timezone).
- Next-occurrence policy: calendar-based progression; on completion, spawn the first occurrence strictly after now_local by iterating the rule starting from the completed occurrence.
- Edit semantics: prompt user for scope each time; "this and future" performs a series split.
- Semantic parsing contract: one JSON schema for both local and cloud parsing; cloud must handle multilingual input.

## Data Model

### Table: todo_series
- id TEXT PRIMARY KEY
- title_template BLOB (encrypted)
- status TEXT NOT NULL  -- active|paused|archived (tbd)
- freq TEXT NOT NULL    -- daily|weekly|monthly|yearly
- interval INTEGER NOT NULL DEFAULT 1
- by_weekdays TEXT      -- JSON array of 1..7 (Mon..Sun), nullable
- by_month_day TEXT     -- JSON array of 1..31, nullable
- time_local TEXT NOT NULL  -- "HH:MM"
- timezone TEXT NOT NULL
- start_local_iso TEXT NULL -- "YYYY-MM-DDTHH:MM:SS" (no tz)
- end_local_iso TEXT NULL
- source_entry_id TEXT NULL
- created_at_ms INTEGER NOT NULL
- updated_at_ms INTEGER NOT NULL

### Table: todos (occurrences)
The existing todos table is rewritten (destructive migration) to add:
- series_id TEXT NULL REFERENCES todo_series(id)
- occurrence_local_iso TEXT NULL
- is_override INTEGER NOT NULL DEFAULT 0
- spawned_from_todo_id TEXT NULL
- UNIQUE(series_id, occurrence_local_iso)

Notes:
- A todo with series_id == NULL is a one-off todo.
- A todo with series_id != NULL represents one scheduled occurrence.

### Table: todo_activities
Add activity type:
- type = 'recurrence_spawn' to audit automatic spawn and support undo.

## Sync / OpLog
- Add op type: todo.series.upsert.v1
- Extend todo.upsert.v1 payload with:
  - series_id
  - occurrence_local_iso
  - is_override
  - spawned_from_todo_id

Apply-side considerations:
- Ensure idempotency using unique constraints.
- Series split is represented as:
  - update old series to set end_local_iso
  - create new series and re-link the current occurrence to it

## API Surface

### Rust (FRB)
- db_upsert_todo_series(...)
- db_get_todo_series(...)
- db_set_todo_status(...) triggers spawn when:
  - todo.series_id is not NULL AND new_status == 'done'
- db_edit_recurring_todo(scope, ...) to implement the 3 edit scopes in one transaction (recommended)

### Dart
- Models: RecurrenceRule, TodoSeries, TodoOccurrenceEditScope.
- Backend: upsertTodoSeries, editRecurringTodo, completeRecurringTodo (optional; or reuse setTodoStatus).

## Completion -> Spawn Flow (Idempotent)
Transaction:
1) Load todo occurrence + series.
2) If todo already done/dismissed, no-op.
3) Set status to done and append status_change activity.
4) Compute next_occurrence_local = next_after(occurrence_local) and fast-forward:
   while next_occurrence_local <= now_local: next_occurrence_local = next_after(next_occurrence_local)
5) Insert next todo occurrence (open) with:
   - series_id
   - occurrence_local_iso = next_occurrence_local
   - due_at_ms = to_utc_ms(next_occurrence_local, series.timezone)
   - spawned_from_todo_id = current todo id
   Conflict on UNIQUE -> treat as already spawned.
6) Append recurrence_spawn activity referencing spawned todo id (tbd payload).

## Editing Scopes
- This occurrence:
  - Update only the current todo. Set is_override=1.
- This and future:
  - Series split:
    - End old series before current occurrence.
    - Create new series with updated rule/template.
    - Move current todo to new series (series_id = new).
- Entire series:
  - Update series rule/template.
  - Optionally update current todo if not override.

## Semantic Parsing (Local + Cloud)

### JSON Schema Extension
For kind=create, add optional recurrence object:
- recurrence:
  - freq
  - interval
  - by_weekdays
  - by_month_day
  - time_local
  - timezone

Local parsing:
- Add a RecurrenceResolver that mirrors LocalTimeResolver token strategy and supports common phrases in:
  - zh, en, ja, ko, es, fr, de
- If rule confidence is low, fall back to LLM parsing (existing semantic parse jobs).

Cloud parsing (Pro):
- Update semantic_parse_message_action prompt to output the same schema.
- The model must handle multilingual input; output field names remain stable English JSON keys.

## Testing
- Rust unit tests:
  - next_after for daily/weekly/monthly/yearly, DST, leap year, month-end.
  - completion spawn idempotency and conflict handling.
  - series split transaction.
- Dart tests:
  - JSON parse of recurrence schema.
  - local recurrence phrase parsing (multilingual cases).
  - UI scope selection branching.

## Milestones
- M1 Data layer rewrite
- M2 Recurrence rule engine
- M3 Complete -> spawn flow
- M4 Edit scope (3 options)
- M5 Semantic parsing (local + cloud)
- M6 Integration + sync regression
