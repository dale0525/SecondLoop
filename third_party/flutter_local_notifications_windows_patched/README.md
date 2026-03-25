# flutter_local_notifications_windows (patched)

Local vendored copy of `flutter_local_notifications_windows` `1.0.3`.

## Local patch

This workspace carries a minimal Windows-specific fix for unpackaged desktop apps:

- `cancel(id)` also removes shown toast history via `Remove(tag, group, appId)`
- `getActiveNotifications()` reads toast history via `GetHistory(appId)`

The goal is to make reminder replacement behave more predictably on Windows when the app is not installed as MSIX.

For the upstream package documentation, see the original project:
https://github.com/MaikuB/flutter_local_notifications/tree/master/flutter_local_notifications_windows
