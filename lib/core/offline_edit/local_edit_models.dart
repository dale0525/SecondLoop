enum LocalEditSyncState {
  clean,
  pending,
  syncing,
  conflict,
  failed,
}

class LocalTextEdit {
  const LocalTextEdit({
    required this.localId,
    required this.remoteId,
    required this.title,
    required this.body,
    required this.baseRevision,
    required this.dirty,
    required this.syncState,
    required this.updatedAtMs,
    required this.lastSyncedAtMs,
    required this.conflictRemoteRevision,
    required this.conflictRemoteTitle,
    required this.conflictRemoteBody,
  });

  final String localId;
  final String? remoteId;
  final String title;
  final String body;
  final String? baseRevision;
  final bool dirty;
  final LocalEditSyncState syncState;
  final int updatedAtMs;
  final int? lastSyncedAtMs;
  final String? conflictRemoteRevision;
  final String? conflictRemoteTitle;
  final String? conflictRemoteBody;
}
