import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_note_client.dart';
import 'package:secondloop/core/offline_edit/local_edit_models.dart';
import 'package:secondloop/features/notes/note_list_page.dart';

import '../../test_i18n.dart';

void main() {
  test('mergeNoteListEntries preserves remote revisions for saved notes', () {
    final entries = mergeNoteListEntries(
      const [
        RuntimeNote(
          id: 'note-1',
          title: 'Remote title',
          body: 'Remote body',
          revision: 'rev-remote',
          updatedAtMs: 2000,
        ),
      ],
      const <LocalTextEdit>[],
    );

    expect(entries, hasLength(1));
    expect(entries.single.id, 'note-1');
    expect(entries.single.baseRevision, 'rev-remote');
  });

  testWidgets('delete action passes the selected entry with base revision',
      (tester) async {
    NoteListEntry? deleted;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NoteListPage(
            entries: const [
              NoteListEntry(
                id: 'note-1',
                title: 'Remote title',
                bodyPreview: 'Remote body',
                updatedAtMs: 2000,
                baseRevision: 'rev-remote',
              ),
            ],
            onDeleteNote: (entry) async {
              deleted = entry;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('note_list_delete_note-1')));
    await tester.pump();

    expect(deleted?.id, 'note-1');
    expect(deleted?.baseRevision, 'rev-remote');
  });
}
