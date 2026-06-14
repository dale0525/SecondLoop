# Restore composer record and Markdown actions

## Goal

Restore the chat composer recording action and expanded Markdown editor entry, with responsive placement across narrow and wide app widths.

## Requirements

- Restore visible composer controls for:
  - attaching files
  - recording audio where the current platform supports recording
  - opening the expanded Markdown editor
  - sending the current draft
- Wire the Markdown control to the existing `ChatMarkdownEditorPage` flow so
  saved text returns to the simple composer and pasted editor attachments are
  preserved as draft attachments.
- Wire the recording control to the existing `record` package and attachment
  draft send path so a completed recording can be sent through the same
  conversation pipeline as other attachments.
- Keep the controls usable at narrow and wide app widths without text overflow
  or overlapping buttons.
- Preserve existing busy-state behavior: input actions are disabled while a
  message is being sent or the assistant is thinking.

## Acceptance Criteria

- [ ] Desktop workbench composer shows stable attach, Markdown, record, and
  send controls at normal widths.
- [ ] Narrow composer layouts wrap secondary controls without clipping the text
  input or send button.
- [ ] Markdown editor opens from the composer, returns saved text, and merges
  editor draft attachments into pending attachments.
- [ ] Recording is unavailable on unsupported platforms and starts/stops on
  supported native platforms.
- [ ] Stopping a recording adds an audio draft that can be sent by the existing
  send path.
- [ ] Widget coverage verifies the restored entry buttons and responsive
  narrow layout.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
