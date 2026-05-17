import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_note_client.dart';
import 'package:secondloop/core/offline_edit/local_edit_models.dart';
import 'package:secondloop/core/offline_edit/local_edit_store.dart';
import 'package:secondloop/core/offline_edit/local_edit_sync_service.dart';

void main() {
  late LocalEditStore store;
  var clock = 1000;

  setUp(() {
    store = LocalEditStore.inMemory();
    clock = 1000;
  });

  tearDown(() async {
    await store.close();
  });

  test('flushPending saves pending edits and marks them synced', () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Local title',
      body: 'Local body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );
    late String seenNoteId;

    final service = LocalEditSyncService(
      store: store,
      vaultId: 'vault-1',
      nowMs: () => clock += 100,
      saveNote: ({
        required vaultId,
        required noteId,
        required title,
        required body,
        required baseRevision,
      }) async {
        expect(vaultId, 'vault-1');
        seenNoteId = noteId;
        expect(title, 'Local title');
        expect(body, 'Local body');
        expect(baseRevision, 'rev-1');
        return const RuntimeNote(
          id: 'note-1',
          title: 'Local title',
          body: 'Local body',
          revision: 'rev-2',
          updatedAtMs: 1500,
        );
      },
    );

    final result = await service.flushPending();
    final saved = await store.readByLocalId(draft.localId);

    expect(seenNoteId, 'note-1');
    expect(result.synced, 1);
    expect(result.conflicts, 0);
    expect(result.failed, 0);
    expect(saved, isNotNull);
    expect(saved!.remoteId, 'note-1');
    expect(saved.baseRevision, 'rev-2');
    expect(saved.dirty, false);
    expect(saved.syncState, LocalEditSyncState.clean);
    expect(saved.lastSyncedAtMs, 1100);
  });

  test('flushPending stores conflict details from runtime conflict', () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Local title',
      body: 'Local body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );

    final service = LocalEditSyncService(
      store: store,
      vaultId: 'vault-1',
      nowMs: () => clock += 100,
      saveNote: ({
        required vaultId,
        required noteId,
        required title,
        required body,
        required baseRevision,
      }) async {
        throw const RuntimeNoteConflictException(
          remote: RuntimeNote(
            id: 'note-1',
            title: 'Remote title',
            body: 'Remote body',
            revision: 'rev-remote',
            updatedAtMs: 1500,
          ),
        );
      },
    );

    final result = await service.flushPending();
    final conflicted = await store.readByLocalId(draft.localId);

    expect(result.synced, 0);
    expect(result.conflicts, 1);
    expect(result.failed, 0);
    expect(conflicted, isNotNull);
    expect(conflicted!.syncState, LocalEditSyncState.conflict);
    expect(conflicted.dirty, true);
    expect(conflicted.title, 'Local title');
    expect(conflicted.body, 'Local body');
    expect(conflicted.conflictRemoteRevision, 'rev-remote');
    expect(conflicted.conflictRemoteTitle, 'Remote title');
    expect(conflicted.conflictRemoteBody, 'Remote body');
  });

  test('flushPending marks non-conflict failures retryable as failed',
      () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Local title',
      body: 'Local body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );
    var attempts = 0;

    final service = LocalEditSyncService(
      store: store,
      vaultId: 'vault-1',
      nowMs: () => clock += 100,
      saveNote: ({
        required vaultId,
        required noteId,
        required title,
        required body,
        required baseRevision,
      }) async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('offline');
        }
        return const RuntimeNote(
          id: 'note-1',
          title: 'Local title',
          body: 'Local body',
          revision: 'rev-2',
          updatedAtMs: 1500,
        );
      },
    );

    final failedResult = await service.flushPending();
    final failed = await store.readByLocalId(draft.localId);

    expect(failedResult.failed, 1);
    expect(failed, isNotNull);
    expect(failed!.syncState, LocalEditSyncState.failed);
    expect(failed.dirty, true);

    final retriedResult = await service.flushPending();
    final synced = await store.readByLocalId(draft.localId);

    expect(retriedResult.synced, 1);
    expect(attempts, 2);
    expect(synced!.syncState, LocalEditSyncState.clean);
    expect(synced.dirty, false);
  });
}
