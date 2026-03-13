import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/chat/chat_markdown_attachment_refs.dart';
import 'package:secondloop/features/chat/chat_markdown_editor_page.dart';

import 'test_i18n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS cmd+V pastes image into markdown editor', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      final harnessKey = GlobalKey<_EditorHarnessState>();
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: EditorHarness(
              key: harnessKey,
              pastedImageReader: () async => ChatMarkdownPastedImageData(
                bytes: _pngBytes(),
                mimeType: 'image/png',
                filename: 'pasted.png',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open_editor')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_markdown_editor_page')),
          findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('chat_markdown_editor_input')),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey('chat_markdown_editor_input')),
      );
      final text = textField.controller?.text ?? '';
      expect(text, contains('![Image]('));
      expect(text, contains(buildDraftMarkdownImageSource('markdown_draft_1')));

      await tester.tap(find.byKey(const ValueKey('chat_markdown_editor_save')));
      await tester.pumpAndSettle();

      final result = harnessKey.currentState?.result;
      expect(result, isNotNull);
      expect(result?.draftAttachments, hasLength(1));
      expect(result?.draftAttachments.single.localId, 'markdown_draft_1');
      expect(result?.draftAttachments.single.normalizedFilename, 'pasted.png');
      expect(result?.draftAttachments.single.normalizedMimeType, 'image/png');
      expect(result?.text,
          contains(buildDraftMarkdownImageSource('markdown_draft_1')));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows ctrl+V pastes image into markdown editor',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    try {
      final harnessKey = GlobalKey<_EditorHarnessState>();
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: EditorHarness(
              key: harnessKey,
              pastedImageReader: () async => ChatMarkdownPastedImageData(
                bytes: _pngBytes(),
                mimeType: 'image/png',
                filename: 'ctrl-v.png',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open_editor')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('chat_markdown_editor_input')),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey('chat_markdown_editor_input')),
      );
      final text = textField.controller?.text ?? '';
      expect(text, contains(buildDraftMarkdownImageSource('markdown_draft_1')));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class EditorHarness extends StatefulWidget {
  const EditorHarness({super.key, required this.pastedImageReader});

  final Future<ChatMarkdownPastedImageData?> Function() pastedImageReader;

  @override
  State<EditorHarness> createState() => _EditorHarnessState();
}

class _EditorHarnessState extends State<EditorHarness> {
  ChatMarkdownEditorResult? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const ValueKey('open_editor'),
          onPressed: () async {
            final next =
                await Navigator.of(context).push<ChatMarkdownEditorResult>(
              MaterialPageRoute(
                builder: (context) => ChatMarkdownEditorPage(
                  initialText: '',
                  pastedImageReader: widget.pastedImageReader,
                ),
              ),
            );
            if (!mounted) return;
            setState(() => result = next);
          },
          child: const Text('Open'),
        ),
      ),
    );
  }
}

Uint8List _pngBytes() => Uint8List.fromList(const <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      0x00,
      0x00,
      0x00,
      0x0d,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1f,
      0x15,
      0xc4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0a,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9c,
      0x63,
      0xf8,
      0xcf,
      0xc0,
      0x00,
      0x00,
      0x03,
      0x01,
      0x01,
      0x00,
      0x18,
      0xdd,
      0x8d,
      0xb1,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4e,
      0x44,
      0xae,
      0x42,
      0x60,
      0x82,
    ]);
