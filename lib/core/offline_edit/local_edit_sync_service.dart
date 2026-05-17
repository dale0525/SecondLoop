import '../cloud/runtime_note_client.dart';
import 'local_edit_models.dart';
import 'local_edit_store.dart';

typedef RuntimeNoteSaveCallback = Future<RuntimeNote> Function({
  required String vaultId,
  required String noteId,
  required String title,
  required String body,
  required String? baseRevision,
});

class LocalEditSyncResult {
  const LocalEditSyncResult({
    required this.synced,
    required this.conflicts,
    required this.failed,
  });

  final int synced;
  final int conflicts;
  final int failed;
}

class LocalEditSyncService {
  LocalEditSyncService({
    required LocalEditStore store,
    required String vaultId,
    required int Function() nowMs,
    RuntimeNoteClient? noteClient,
    RuntimeNoteSaveCallback? saveNote,
  })  : _store = store,
        _vaultId = vaultId,
        _nowMs = nowMs,
        _saveNote = saveNote ?? noteClient!.saveNote;

  final LocalEditStore _store;
  final String _vaultId;
  final int Function() _nowMs;
  final RuntimeNoteSaveCallback _saveNote;

  Future<LocalEditSyncResult> flushPending() async {
    final edits = await _store.listRetryableEdits();
    var synced = 0;
    var conflicts = 0;
    var failed = 0;

    for (final edit in edits) {
      try {
        final remote = await _saveNote(
          vaultId: _vaultId,
          noteId: _noteIdForEdit(edit),
          title: edit.title,
          body: edit.body,
          baseRevision: edit.baseRevision,
        );
        await _store.markSynced(
          localId: edit.localId,
          remoteId: remote.id,
          revision: remote.revision,
          nowMs: _nowMs(),
        );
        synced += 1;
      } on RuntimeNoteConflictException catch (error) {
        await _store.markConflict(
          localId: edit.localId,
          remoteRevision: error.remote.revision,
          remoteTitle: error.remote.title,
          remoteBody: error.remote.body,
          nowMs: _nowMs(),
        );
        conflicts += 1;
      } catch (_) {
        await _store.markFailed(localId: edit.localId, nowMs: _nowMs());
        failed += 1;
      }
    }

    return LocalEditSyncResult(
      synced: synced,
      conflicts: conflicts,
      failed: failed,
    );
  }

  static String _noteIdForEdit(LocalTextEdit edit) {
    return edit.remoteId ?? edit.localId;
  }
}
