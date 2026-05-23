# Flutter UI Guidelines

This directory documents the current Flutter UI patterns in the app. It should
not describe React, web-server routes, or private backend implementation
details.

## Guides

| Guide | Scope |
|-------|-------|
| [Directory Structure](./directory-structure.md) | App shell, feature folders, UI primitives, web entry points |
| [Component Guidelines](./component-guidelines.md) | Widget composition, design tokens, keys, i18n, responsive layout |
| [State Management](./state-management.md) | Inherited scopes, controllers, form fields, async busy state |
| [Type Safety](./type-safety.md) | Dart model, enum, JSON, and callback conventions used by UI code |
| [Quality Guidelines](./quality-guidelines.md) | Widget tests, HTTP client tests, accessibility handles, verification |

Keep rules concrete and backed by files in `lib/` or `test/`.
