import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/offline_edit/local_edit_models.dart';
import 'package:secondloop/core/offline_edit/local_edit_store.dart';

void main() {
  late LocalEditStore store;

  setUp(() {
    store = LocalEditStore.inMemory();
  });

  tearDown(() async {
    await store.close();
  });

  test('saveDraft stores pending dirty edit fields', () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Draft title',
      body: 'Draft body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );

    expect(draft.localId, isNotEmpty);
    expect(draft.remoteId, 'note-1');
    expect(draft.title, 'Draft title');
    expect(draft.body, 'Draft body');
    expect(draft.baseRevision, 'rev-1');
    expect(draft.dirty, true);
    expect(draft.syncState, LocalEditSyncState.pending);
    expect(draft.updatedAtMs, 1000);
    expect(draft.lastSyncedAtMs, isNull);
  });

  test('local ids are unique across stores for same timestamp', () async {
    final otherStore = LocalEditStore.inMemory();
    addTearDown(otherStore.close);

    final first = await store.saveDraft(
      remoteId: null,
      title: 'Local note',
      body: 'First body',
      baseRevision: null,
      nowMs: 1000,
    );
    final second = await otherStore.saveDraft(
      remoteId: null,
      title: 'Local note',
      body: 'Second body',
      baseRevision: null,
      nowMs: 1000,
    );

    expect(first.localId, startsWith('local-1000-'));
    expect(second.localId, startsWith('local-1000-'));
    expect(first.localId, isNot(second.localId));
  });

  test('listPendingEdits returns pending edits in updated-time order',
      () async {
    final first = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Older',
      body: 'Older body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );
    final second = await store.saveDraft(
      remoteId: 'note-2',
      title: 'Newer',
      body: 'Newer body',
      baseRevision: 'rev-2',
      nowMs: 2000,
    );

    final pending = await store.listPendingEdits();

    expect(pending.map((edit) => edit.localId), <String>[
      first.localId,
      second.localId,
    ]);
  });

  test('markSynced stores remote revision and moves edit to clean', () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Draft title',
      body: 'Draft body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );

    await store.markSynced(
      localId: draft.localId,
      remoteId: 'note-1',
      revision: 'rev-2',
      nowMs: 2000,
    );

    final saved = await store.readByLocalId(draft.localId);

    expect(saved, isNotNull);
    expect(saved!.remoteId, 'note-1');
    expect(saved.baseRevision, 'rev-2');
    expect(saved.dirty, false);
    expect(saved.syncState, LocalEditSyncState.clean);
    expect(saved.updatedAtMs, 2000);
    expect(saved.lastSyncedAtMs, 2000);
    expect(await store.listPendingEdits(), isEmpty);
  });

  test('markConflict preserves local body and stores remote conflict fields',
      () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Local title',
      body: 'Local body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );

    await store.markConflict(
      localId: draft.localId,
      remoteRevision: 'rev-remote',
      remoteTitle: 'Remote title',
      remoteBody: 'Remote body',
      nowMs: 2000,
    );

    final conflicted = await store.readByRemoteId('note-1');

    expect(conflicted, isNotNull);
    expect(conflicted!.title, 'Local title');
    expect(conflicted.body, 'Local body');
    expect(conflicted.dirty, true);
    expect(conflicted.syncState, LocalEditSyncState.conflict);
    expect(conflicted.updatedAtMs, 2000);
    expect(conflicted.conflictRemoteRevision, 'rev-remote');
    expect(conflicted.conflictRemoteTitle, 'Remote title');
    expect(conflicted.conflictRemoteBody, 'Remote body');
  });

  test('saveDraft updates existing remote edit and clears conflict fields',
      () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Local title',
      body: 'Local body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );

    await store.markConflict(
      localId: draft.localId,
      remoteRevision: 'rev-remote',
      remoteTitle: 'Remote title',
      remoteBody: 'Remote body',
      nowMs: 2000,
    );

    final resolvedDraft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Resolved title',
      body: 'Resolved body',
      baseRevision: 'rev-remote',
      nowMs: 3000,
    );
    final latestDraft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Latest title',
      body: 'Latest body',
      baseRevision: 'rev-latest',
      nowMs: 4000,
    );

    final pending = await store.listPendingEdits();
    final saved = await store.readByRemoteId('note-1');

    expect(resolvedDraft.localId, draft.localId);
    expect(latestDraft.localId, draft.localId);
    expect(pending, hasLength(1));
    expect(pending.single.localId, draft.localId);
    expect(saved, isNotNull);
    expect(saved!.localId, draft.localId);
    expect(saved.title, 'Latest title');
    expect(saved.body, 'Latest body');
    expect(saved.baseRevision, 'rev-latest');
    expect(saved.dirty, true);
    expect(saved.syncState, LocalEditSyncState.pending);
    expect(saved.updatedAtMs, 4000);
    expect(saved.conflictRemoteRevision, isNull);
    expect(saved.conflictRemoteTitle, isNull);
    expect(saved.conflictRemoteBody, isNull);
  });

  test('saveDraft preserves last synced timestamp for remote edit', () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Clean title',
      body: 'Clean body',
      baseRevision: 'rev-1',
      nowMs: 1000,
    );

    await store.markSynced(
      localId: draft.localId,
      remoteId: 'note-1',
      revision: 'rev-2',
      nowMs: 2000,
    );

    final edited = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Edited title',
      body: 'Edited body',
      baseRevision: 'rev-2',
      nowMs: 3000,
    );

    expect(edited.localId, draft.localId);
    expect(edited.baseRevision, 'rev-2');
    expect(edited.dirty, true);
    expect(edited.syncState, LocalEditSyncState.pending);
    expect(edited.updatedAtMs, 3000);
    expect(edited.lastSyncedAtMs, 2000);
    expect(await store.listPendingEdits(), hasLength(1));
  });
}
