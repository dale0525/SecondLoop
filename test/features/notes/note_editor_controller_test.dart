import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_note_client.dart';
import 'package:secondloop/core/offline_edit/local_edit_models.dart';
import 'package:secondloop/core/offline_edit/local_edit_store.dart';
import 'package:secondloop/core/offline_edit/local_edit_sync_service.dart';
import 'package:secondloop/features/notes/note_editor_controller.dart';

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

  test('editing while offline saves into LocalEditStore', () async {
    final controller = _controller(
      store: store,
      isOnline: false,
      saveNote: _successfulSave,
      nowMs: () => clock += 100,
    );

    await controller.save(title: 'Offline title', body: 'Offline body');

    final pending = await store.listPendingEdits();
    expect(controller.status, NoteEditorStatus.pending);
    expect(pending, hasLength(1));
    expect(pending.single.title, 'Offline title');
    expect(pending.single.body, 'Offline body');
    expect(pending.single.syncState, LocalEditSyncState.pending);
  });

  test('online save flushes through LocalEditSyncService', () async {
    final seenTitles = <String>[];
    final controller = _controller(
      store: store,
      isOnline: true,
      saveNote: ({
        required vaultId,
        required noteId,
        required title,
        required body,
        required baseRevision,
      }) async {
        seenTitles.add(title);
        return RuntimeNote(
          id: noteId,
          title: title,
          body: body,
          revision: 'rev-1',
          updatedAtMs: 2000,
        );
      },
      nowMs: () => clock += 100,
    );

    await controller.save(title: 'Online title', body: 'Online body');

    expect(seenTitles, ['Online title']);
    expect(controller.status, NoteEditorStatus.clean);
    expect(controller.baseRevision, 'rev-1');
    expect(await store.listPendingEdits(), isEmpty);
  });

  test('conflict state exposes local and remote text', () async {
    final controller = _controller(
      store: store,
      remoteId: 'note-1',
      baseRevision: 'rev-local',
      isOnline: true,
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
            updatedAtMs: 2000,
          ),
        );
      },
      nowMs: () => clock += 100,
    );

    await controller.save(title: 'Local title', body: 'Local body');

    expect(controller.status, NoteEditorStatus.conflict);
    expect(controller.title, 'Local title');
    expect(controller.body, 'Local body');
    expect(controller.conflictRemoteTitle, 'Remote title');
    expect(controller.conflictRemoteBody, 'Remote body');
    expect(controller.conflictRemoteRevision, 'rev-remote');
  });

  test('load fetches existing note when online', () async {
    final controller = _controller(
      store: store,
      remoteId: 'note-1',
      isOnline: true,
      saveNote: _successfulSave,
      loadNote: (noteId) async {
        expect(noteId, 'note-1');
        return const RuntimeNote(
          id: 'note-1',
          title: 'Remote title',
          body: 'Remote body',
          revision: 'rev-2',
          updatedAtMs: 2000,
        );
      },
      nowMs: () => clock += 100,
    );

    await controller.load();

    expect(controller.status, NoteEditorStatus.clean);
    expect(controller.title, 'Remote title');
    expect(controller.body, 'Remote body');
    expect(controller.baseRevision, 'rev-2');
  });

  test('load keeps pending local edit when online', () async {
    await store.saveDraft(
      remoteId: 'note-1',
      title: 'Pending local title',
      body: 'Pending local body',
      baseRevision: 'rev-local',
      nowMs: clock += 100,
    );
    var loadCalls = 0;
    final controller = _controller(
      store: store,
      remoteId: 'note-1',
      isOnline: true,
      saveNote: _successfulSave,
      loadNote: (noteId) async {
        loadCalls += 1;
        return const RuntimeNote(
          id: 'note-1',
          title: 'Remote title',
          body: 'Remote body',
          revision: 'rev-remote',
          updatedAtMs: 2000,
        );
      },
      nowMs: () => clock += 100,
    );

    await controller.load();

    expect(loadCalls, 0);
    expect(controller.status, NoteEditorStatus.pending);
    expect(controller.title, 'Pending local title');
    expect(controller.body, 'Pending local body');
    expect(controller.baseRevision, 'rev-local');
  });

  test('load keeps failed local edit when online', () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Failed local title',
      body: 'Failed local body',
      baseRevision: 'rev-local',
      nowMs: clock += 100,
    );
    await store.markFailed(localId: draft.localId, nowMs: clock += 100);
    var loadCalls = 0;
    final controller = _controller(
      store: store,
      remoteId: 'note-1',
      isOnline: true,
      saveNote: _successfulSave,
      loadNote: (noteId) async {
        loadCalls += 1;
        return const RuntimeNote(
          id: 'note-1',
          title: 'Remote title',
          body: 'Remote body',
          revision: 'rev-remote',
          updatedAtMs: 2000,
        );
      },
      nowMs: () => clock += 100,
    );

    await controller.load();

    expect(loadCalls, 0);
    expect(controller.status, NoteEditorStatus.failed);
    expect(controller.title, 'Failed local title');
    expect(controller.body, 'Failed local body');
  });

  test('load keeps conflict local and remote text when online', () async {
    final draft = await store.saveDraft(
      remoteId: 'note-1',
      title: 'Conflict local title',
      body: 'Conflict local body',
      baseRevision: 'rev-local',
      nowMs: clock += 100,
    );
    await store.markConflict(
      localId: draft.localId,
      remoteRevision: 'rev-conflict',
      remoteTitle: 'Conflict remote title',
      remoteBody: 'Conflict remote body',
      nowMs: clock += 100,
    );
    var loadCalls = 0;
    final controller = _controller(
      store: store,
      remoteId: 'note-1',
      isOnline: true,
      saveNote: _successfulSave,
      loadNote: (noteId) async {
        loadCalls += 1;
        return const RuntimeNote(
          id: 'note-1',
          title: 'Remote title',
          body: 'Remote body',
          revision: 'rev-remote',
          updatedAtMs: 2000,
        );
      },
      nowMs: () => clock += 100,
    );

    await controller.load();

    expect(loadCalls, 0);
    expect(controller.status, NoteEditorStatus.conflict);
    expect(controller.title, 'Conflict local title');
    expect(controller.body, 'Conflict local body');
    expect(controller.conflictRemoteTitle, 'Conflict remote title');
    expect(controller.conflictRemoteBody, 'Conflict remote body');
    expect(controller.conflictRemoteRevision, 'rev-conflict');
  });

  test('controller imports stay out of legacy runtime paths', () {
    final source = File(
      'lib/features/notes/note_editor_controller.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('NativeAppBackend')));
    expect(source, isNot(contains('SyncEngine')));
  });
}

NoteEditorController _controller({
  required LocalEditStore store,
  required bool isOnline,
  required RuntimeNoteSaveCallback saveNote,
  required int Function() nowMs,
  String vaultId = 'vault-1',
  String? remoteId,
  String? baseRevision,
  RuntimeNoteLoader? loadNote,
}) {
  return NoteEditorController(
    store: store,
    syncService: LocalEditSyncService(
      store: store,
      vaultId: vaultId,
      saveNote: saveNote,
      nowMs: nowMs,
    ),
    vaultId: vaultId,
    remoteId: remoteId,
    baseRevision: baseRevision,
    isOnline: () => isOnline,
    nowMs: nowMs,
    loadNote: loadNote,
  );
}

Future<RuntimeNote> _successfulSave({
  required String vaultId,
  required String noteId,
  required String title,
  required String body,
  required String? baseRevision,
}) async {
  return RuntimeNote(
    id: noteId,
    title: title,
    body: body,
    revision: 'rev-1',
    updatedAtMs: 2000,
  );
}
