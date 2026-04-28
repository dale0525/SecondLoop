part of 'chat_page.dart';

const _kChatTaskPrioritySyncRefreshDebounce = Duration(milliseconds: 250);

extension _ChatPageStateTaskPriorityRefresh on _ChatPageState {
  void _cancelTaskPrioritySyncRefreshDebounce() {
    _taskPrioritySyncRefreshDebounceTimer?.cancel();
    _taskPrioritySyncRefreshDebounceTimer = null;
  }

  void _scheduleTaskPrioritySyncRefresh() {
    final store = _taskPriorityStore;
    if (store == null) return;

    store.markDirty();
    _taskPrioritySyncRefreshDebounceTimer?.cancel();
    _taskPrioritySyncRefreshDebounceTimer = Timer(
      _kChatTaskPrioritySyncRefreshDebounce,
      () {
        _taskPrioritySyncRefreshDebounceTimer = null;
        if (!mounted || !identical(store, _taskPriorityStore)) return;
        unawaited(store.refresh(force: true));
      },
    );
  }

  void _refreshTaskPriorityNow() {
    _cancelTaskPrioritySyncRefreshDebounce();
    final store = _taskPriorityStore;
    if (store == null) return;

    store.markDirty();
    unawaited(store.refresh(force: true));
  }
}
