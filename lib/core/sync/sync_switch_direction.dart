enum SyncSwitchDirection {
  localReplacesRemote,
  remoteReplacesLocal,
  merge,
}

final class SyncRemoteReplaceCommittedException implements Exception {
  const SyncRemoteReplaceCommittedException(this.cause);

  final Object cause;

  @override
  String toString() => '$cause';
}
