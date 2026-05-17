import 'package:sqlite3/sqlite3.dart';

import 'local_edit_models.dart';

class LocalEditStore {
  LocalEditStore._(this._database) {
    _database.execute(_schema);
  }

  factory LocalEditStore.inMemory() {
    return LocalEditStore._(sqlite3.openInMemory());
  }

  final Database _database;
  var _localIdSequence = 0;

  Future<LocalTextEdit> saveDraft({
    String? remoteId,
    required String title,
    required String body,
    required String? baseRevision,
    required int nowMs,
  }) async {
    if (remoteId != null) {
      final existing = await readByRemoteId(remoteId);
      if (existing != null) {
        _database.execute(
          '''
          UPDATE local_text_edits
          SET title = ?,
              body = ?,
              base_revision = ?,
              dirty = ?,
              sync_state = ?,
              updated_at_ms = ?,
              conflict_remote_revision = NULL,
              conflict_remote_title = NULL,
              conflict_remote_body = NULL
          WHERE local_id = ?
          ''',
          [
            title,
            body,
            baseRevision,
            1,
            LocalEditSyncState.pending.name,
            nowMs,
            existing.localId,
          ],
        );
        return (await readByLocalId(existing.localId))!;
      }
    }

    final localId = _createLocalId(nowMs);
    _database.execute(
      '''
      INSERT INTO local_text_edits (
        local_id,
        remote_id,
        title,
        body,
        base_revision,
        dirty,
        sync_state,
        updated_at_ms,
        last_synced_at_ms,
        conflict_remote_revision,
        conflict_remote_title,
        conflict_remote_body
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        localId,
        remoteId,
        title,
        body,
        baseRevision,
        1,
        LocalEditSyncState.pending.name,
        nowMs,
        null,
        null,
        null,
        null,
      ],
    );

    return (await readByLocalId(localId))!;
  }

  Future<List<LocalTextEdit>> listPendingEdits() async {
    final rows = _database.select(
      '''
      SELECT *
      FROM local_text_edits
      WHERE sync_state = ?
      ORDER BY updated_at_ms ASC, local_id ASC
      ''',
      [LocalEditSyncState.pending.name],
    );
    return rows.map(_editFromRow).toList(growable: false);
  }

  Future<LocalTextEdit?> readByRemoteId(String remoteId) async {
    final rows = _database.select(
      '''
      SELECT *
      FROM local_text_edits
      WHERE remote_id = ?
      ORDER BY updated_at_ms DESC, local_id DESC
      LIMIT 1
      ''',
      [remoteId],
    );
    return rows.isEmpty ? null : _editFromRow(rows.first);
  }

  Future<LocalTextEdit?> readByLocalId(String localId) async {
    final rows = _database.select(
      '''
      SELECT *
      FROM local_text_edits
      WHERE local_id = ?
      LIMIT 1
      ''',
      [localId],
    );
    return rows.isEmpty ? null : _editFromRow(rows.first);
  }

  Future<void> markSynced({
    required String localId,
    required String remoteId,
    required String revision,
    required int nowMs,
  }) async {
    _database.execute(
      '''
      UPDATE local_text_edits
      SET remote_id = ?,
          base_revision = ?,
          dirty = ?,
          sync_state = ?,
          updated_at_ms = ?,
          last_synced_at_ms = ?,
          conflict_remote_revision = NULL,
          conflict_remote_title = NULL,
          conflict_remote_body = NULL
      WHERE local_id = ?
      ''',
      [
        remoteId,
        revision,
        0,
        LocalEditSyncState.clean.name,
        nowMs,
        nowMs,
        localId,
      ],
    );
  }

  Future<void> markConflict({
    required String localId,
    required String remoteRevision,
    required String remoteTitle,
    required String remoteBody,
    required int nowMs,
  }) async {
    _database.execute(
      '''
      UPDATE local_text_edits
      SET dirty = ?,
          sync_state = ?,
          updated_at_ms = ?,
          conflict_remote_revision = ?,
          conflict_remote_title = ?,
          conflict_remote_body = ?
      WHERE local_id = ?
      ''',
      [
        1,
        LocalEditSyncState.conflict.name,
        nowMs,
        remoteRevision,
        remoteTitle,
        remoteBody,
        localId,
      ],
    );
  }

  Future<void> close() async {
    _database.dispose();
  }

  String _createLocalId(int nowMs) {
    final sequence = _localIdSequence++;
    return 'local-$nowMs-$sequence';
  }

  static LocalTextEdit _editFromRow(Row row) {
    return LocalTextEdit(
      localId: row['local_id'] as String,
      remoteId: row['remote_id'] as String?,
      title: row['title'] as String,
      body: row['body'] as String,
      baseRevision: row['base_revision'] as String?,
      dirty: row['dirty'] == 1,
      syncState: _syncStateFromName(row['sync_state'] as String),
      updatedAtMs: row['updated_at_ms'] as int,
      lastSyncedAtMs: row['last_synced_at_ms'] as int?,
      conflictRemoteRevision: row['conflict_remote_revision'] as String?,
      conflictRemoteTitle: row['conflict_remote_title'] as String?,
      conflictRemoteBody: row['conflict_remote_body'] as String?,
    );
  }

  static LocalEditSyncState _syncStateFromName(String name) {
    return LocalEditSyncState.values.firstWhere(
      (state) => state.name == name,
    );
  }

  static const _schema = '''
CREATE TABLE IF NOT EXISTS local_text_edits (
  local_id TEXT PRIMARY KEY,
  remote_id TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  base_revision TEXT,
  dirty INTEGER NOT NULL,
  sync_state TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  last_synced_at_ms INTEGER,
  conflict_remote_revision TEXT,
  conflict_remote_title TEXT,
  conflict_remote_body TEXT
);
''';
}
