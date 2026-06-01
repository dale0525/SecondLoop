import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/app_shell_style.dart';
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

  testWidgets('renders the vault index structure from the Stitch design',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: NoteListPage(entries: <NoteListEntry>[]),
        ),
      ),
    );

    expect(find.text('Vault Index'), findsOneWidget);
    expect(find.text('Search memories, files, notes...'), findsOneWidget);
    expect(find.text('Memories'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Research'), findsOneWidget);
    expect(find.text('Recent Additions'), findsOneWidget);
    expect(find.text('View All'), findsOneWidget);
    expect(find.text('0 items'), findsOneWidget);
    expect(find.text('No data yet'), findsNWidgets(3));
    expect(find.text('No recent additions'), findsOneWidget);
    expect(find.text('2,401 entries'), findsNothing);
    expect(find.text('142 items'), findsNothing);
    expect(find.byKey(const ValueKey('note_list_create_button')), findsNothing);
  });

  testWidgets('keeps vault actions focused on viewing existing content',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: NoteListPage(
            entries: [
              NoteListEntry(
                id: 'note-1',
                title: 'Alpha note',
                updatedAtMs: 3000,
              ),
              NoteListEntry(
                id: 'note-2',
                title: 'Beta note',
                updatedAtMs: 2000,
              ),
              NoteListEntry(
                id: 'note-3',
                title: 'Gamma note',
                updatedAtMs: 1000,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Alpha note'), findsOneWidget);
    expect(find.text('Beta note'), findsOneWidget);
    expect(find.text('Gamma note'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('note_list_view_all_button')));
    await tester.pump();

    expect(find.text('Gamma note'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('note_list_category_notes')));
    await tester.tap(find.byKey(const ValueKey('note_list_category_memories')));
    await tester.tap(find.byKey(const ValueKey('note_list_category_files')));
    await tester.tap(find.byKey(const ValueKey('note_list_category_research')));
    await tester.pump();

    expect(find.byKey(const ValueKey('note_list_create_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps search field aligned across audited widths',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in <double>[320, 390, 768, 1200, 1600]) {
      await tester.binding.setSurfaceSize(Size(width, 884));
      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            home: NoteListPage(entries: <NoteListEntry>[]),
          ),
        ),
      );
      await tester.pump();

      final fieldRect = tester.getRect(
        find.byKey(const ValueKey('note_list_search_field')),
      );
      final viewAllRect = tester.getRect(
        find.byKey(const ValueKey('note_list_view_all_button')),
      );
      final horizontalMargin = width >= 768 ? 32.0 : 16.0;
      final expectedMaxWidth =
          (width - horizontalMargin * 2).clamp(0.0, 672.0).toDouble();

      expect(fieldRect.left, greaterThanOrEqualTo(horizontalMargin - 0.1));
      expect(
          fieldRect.right, lessThanOrEqualTo(width - horizontalMargin + 0.1));
      expect(fieldRect.width, lessThanOrEqualTo(expectedMaxWidth + 0.1));
      expect(fieldRect.height, 45);
      expect(
          viewAllRect.right, lessThanOrEqualTo(width - horizontalMargin + 0.1));
      expect(
          find.byKey(const ValueKey('note_list_create_button')), findsNothing);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('hides duplicated brand bar inside desktop app shell',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AppShellLayoutScope(
            desktopWorkbench: true,
            child: NoteListPage(entries: <NoteListEntry>[]),
          ),
        ),
      ),
    );

    expect(find.text('SecondLoop'), findsNothing);
    expect(find.text('Vault Index'), findsOneWidget);
  });

  testWidgets('long-press delete passes the selected entry with base revision',
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

    await tester.longPress(find.byKey(const ValueKey('note_list_item_note-1')));
    await tester.pump();

    expect(deleted?.id, 'note-1');
    expect(deleted?.baseRevision, 'rev-remote');
  });
}
