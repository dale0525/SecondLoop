import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_note_client.dart';
import 'package:secondloop/core/offline_edit/local_edit_store.dart';
import 'package:secondloop/core/offline_edit/local_edit_sync_service.dart';
import 'package:secondloop/features/notes/note_detail_page.dart';
import 'package:secondloop/features/notes/note_editor_controller.dart';

import '../../test_i18n.dart';

void main() {
  late LocalEditStore store;

  setUp(() {
    store = LocalEditStore.inMemory();
  });

  tearDown(() async {
    await store.close();
  });

  testWidgets('renders note details in the vault design language',
      (tester) async {
    final controller = await _loadedController(store);

    await tester.pumpWidget(_app(controller));

    expect(find.byKey(const ValueKey('note_detail_page')), findsOneWidget);
    expect(find.text('View Detail'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Stitch detail title'), findsOneWidget);
    expect(find.text('Detail body rendered as read-only vault content.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('note_editor_title_field')), findsNothing);
    expect(find.byKey(const ValueKey('note_editor_body_field')), findsNothing);
    expect(find.byKey(const ValueKey('note_editor_save_button')), findsNothing);
  });

  testWidgets('keeps the detail body aligned across audited widths',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in <double>[320, 390, 768, 1200, 1600]) {
      final controller = await _loadedController(store);
      await tester.binding.setSurfaceSize(Size(width, 884));
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      final bodyRect = tester.getRect(
        find.byKey(const ValueKey('note_detail_body_card')),
      );
      final horizontalMargin = width >= 768 ? 32.0 : 16.0;
      final expectedMaxWidth =
          (width - horizontalMargin * 2).clamp(0.0, 1280.0).toDouble();

      expect(bodyRect.left, greaterThanOrEqualTo(horizontalMargin - 0.1));
      expect(bodyRect.right, lessThanOrEqualTo(width - horizontalMargin + 0.1));
      expect(bodyRect.width, lessThanOrEqualTo(expectedMaxWidth + 0.1));
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });
}

Widget _app(NoteEditorController controller) {
  return wrapWithI18n(
    MaterialApp(
      home: NoteDetailPage(controller: controller),
    ),
  );
}

Future<NoteEditorController> _loadedController(LocalEditStore store) async {
  final controller = NoteEditorController(
    store: store,
    syncService: LocalEditSyncService(
      store: store,
      vaultId: 'vault-1',
      saveNote: _successfulSave,
      nowMs: () => 2000,
    ),
    vaultId: 'vault-1',
    remoteId: 'note-1',
    isOnline: () => true,
    nowMs: () => 2000,
    loadNote: (_) async => const RuntimeNote(
      id: 'note-1',
      title: 'Stitch detail title',
      body: 'Detail body rendered as read-only vault content.',
      revision: 'rev-1',
      updatedAtMs: 2000,
    ),
  );
  await controller.load();
  return controller;
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
