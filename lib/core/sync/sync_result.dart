final class SyncPullResult {
  const SyncPullResult({
    required this.applied,
    this.shouldRefreshUi = false,
  });

  final int applied;
  final bool shouldRefreshUi;

  bool get hasAppliedChanges => applied > 0;
}
