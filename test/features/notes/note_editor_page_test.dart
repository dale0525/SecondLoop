import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_note_client.dart';
import 'package:secondloop/core/offline_edit/local_edit_store.dart';
import 'package:secondloop/core/offline_edit/local_edit_sync_service.dart';
import 'package:secondloop/features/notes/note_editor_controller.dart';
import 'package:secondloop/features/notes/note_editor_page.dart';

import '../../test_i18n.dart';

void main() {
  late LocalEditStore store;

  setUp(() {
    store = LocalEditStore.inMemory();
  });

  tearDown(() async {
    await store.close();
  });

  testWidgets('title and body fields render', (tester) async {
    final controller = _controller(store: store, isOnline: false);

    await tester.pumpWidget(_app(controller));

    expect(
        find.byKey(const ValueKey('note_editor_title_field')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('note_editor_body_field')), findsOneWidget);
  });

  testWidgets('offline save shows pending state', (tester) async {
    final controller = _controller(store: store, isOnline: false);

    await tester.pumpWidget(_app(controller));
    await tester.enterText(
      find.byKey(const ValueKey('note_editor_title_field')),
      'Offline title',
    );
    await tester.enterText(
      find.byKey(const ValueKey('note_editor_body_field')),
      'Offline body',
    );
    await tester.tap(find.byKey(const ValueKey('note_editor_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('conflict panel shows local and remote content', (tester) async {
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
    );

    await tester.pumpWidget(_app(controller));
    await tester.enterText(
      find.byKey(const ValueKey('note_editor_title_field')),
      'Local title',
    );
    await tester.enterText(
      find.byKey(const ValueKey('note_editor_body_field')),
      'Local body',
    );
    await tester.tap(find.byKey(const ValueKey('note_editor_save_button')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('note_editor_conflict_panel'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('Local body')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Remote body')),
      findsOneWidget,
    );
  });

  testWidgets('body field handles 10000 characters without overflow',
      (tester) async {
    final controller = _controller(store: store, isOnline: false);
    final body = List.filled(10000, 'a').join();

    await tester.pumpWidget(_app(controller));
    await tester.enterText(
      find.byKey(const ValueKey('note_editor_body_field')),
      body,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const ValueKey('note_editor_body_field')), findsOneWidget);
  });

  testWidgets('conflict panel scrolls long local and remote content',
      (tester) async {
    final longBody = List.filled(10000, 'conflict').join(' ');
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
        throw RuntimeNoteConflictException(
          remote: RuntimeNote(
            id: 'note-1',
            title: 'Remote title',
            body: longBody,
            revision: 'rev-remote',
            updatedAtMs: 2000,
          ),
        );
      },
    );

    await tester.pumpWidget(_app(controller));
    await tester.enterText(
      find.byKey(const ValueKey('note_editor_body_field')),
      longBody,
    );
    await tester.tap(find.byKey(const ValueKey('note_editor_save_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('note_editor_conflict_scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app(NoteEditorController controller) {
  return wrapWithI18n(
    MaterialApp(
      home: Scaffold(
        body: NoteEditorPage(controller: controller),
      ),
    ),
  );
}

NoteEditorController _controller({
  required LocalEditStore store,
  required bool isOnline,
  RuntimeNoteSaveCallback? saveNote,
}) {
  return NoteEditorController(
    store: store,
    syncService: LocalEditSyncService(
      store: store,
      vaultId: 'vault-1',
      saveNote: saveNote ?? _successfulSave,
      nowMs: () => 2000,
    ),
    vaultId: 'vault-1',
    remoteId: 'note-1',
    isOnline: () => isOnline,
    nowMs: () => 2000,
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
