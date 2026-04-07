part of 'task_hub_page.dart';

extension _TaskHubPageStatePriorityResolution on _TaskHubPageState {
  void _attachStoreListener() {
    final store = _store;
    if (store == null || identical(store, _observedStore)) {
      return;
    }

    final previousStore = _observedStore;
    final previousListener = _storeListener;
    if (previousStore != null && previousListener != null) {
      previousStore.removeListener(previousListener);
    }

    void onStoreChanged() {
      final currentStore = _store;
      if (!mounted || currentStore == null) return;
      final snapshot = currentStore.snapshot;
      final previousState = _priorityResolutionController.state;
      _priorityResolutionController.consumeSnapshot(snapshot);
      _syncPriorityResolutionTimeout(
        previous: previousState,
        current: _priorityResolutionController.state,
      );
      _handlePriorityAnimationSnapshot(snapshot);
    }

    _observedStore = store;
    _storeListener = onStoreChanged;
    store.addListener(onStoreChanged);
  }

  void _syncPriorityResolutionTimeout({
    required TaskHubPriorityResolutionState previous,
    required TaskHubPriorityResolutionState current,
  }) {
    if (current.status ==
        TaskHubPriorityResolutionStatus.awaitingAiResolution) {
      final alreadyTrackingSameAction =
          previous.actionToken == current.actionToken &&
              previous.status == current.status;
      if (alreadyTrackingSameAction) {
        return;
      }
      _priorityAiPendingTimeoutTimer?.cancel();
      final actionToken = current.actionToken;
      _priorityAiPendingTimeoutTimer = Timer(
        _TaskHubPageState._kPriorityAiPendingTimeout,
        () {
          if (!mounted) return;
          _priorityAiPendingTimeoutTimer = null;
          _pendingPriorityAnimation = null;
          _priorityResolutionController.markLocalFallback(
            actionToken: actionToken,
          );
        },
      );
      return;
    }

    _priorityAiPendingTimeoutTimer?.cancel();
    _priorityAiPendingTimeoutTimer = null;
  }
}
