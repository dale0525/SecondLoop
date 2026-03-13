// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:super_native_extensions/src/native/context.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_markdown_editor_page.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';
import 'package:secondloop/features/chat/chat_markdown_export_image_sources.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'editor export menu exposes pdf action',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await tester.pumpWidget(_buildEditorApp(
          backend: _ExportAttachmentBackend(),
          initialText: 'Hello',
        ));
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('chat_markdown_editor_export_menu'))
              .evaluate()
              .isNotEmpty,
        );

        final menuFinder =
            find.byKey(const ValueKey('chat_markdown_editor_export_menu'));
        final context = tester.element(menuFinder);
        final dynamic menuWidget = tester.widget(menuFinder);
        final List<dynamic> entries =
            List<dynamic>.from(menuWidget.itemBuilder(context));

        expect(
            entries.any((entry) => '${entry.value}'.contains('pdf')), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'editor debug pdf export resolves persisted attachment images',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final backend = _ExportAttachmentBackend();
      String? capturedHtml;

      try {
        await tester.pumpWidget(_buildEditorApp(
          backend: backend,
          initialText: '![saved](secondloop://attachment/sha_pdf)',
          pdfHtmlBuilder: ({
            required markdown,
            required theme,
            required emptyFallback,
            List<AttachmentDraftPayload> draftAttachments =
                const <AttachmentDraftPayload>[],
            readPersistedAttachment,
          }) async {
            final hydratedMarkdown = await inlineMarkdownImageSourcesAsDataUrls(
              markdown,
              draftAttachments: draftAttachments.cast(),
              readPersistedAttachment: readPersistedAttachment,
            );
            return '<html><body>$hydratedMarkdown</body></html>';
          },
          pdfExporter: ({required html, pageBackgroundColorHex}) async {
            capturedHtml = html;
            return Uint8List.fromList('%PDF-1.4'.codeUnits);
          },
        ));

        final dynamic state = tester.state(find.byType(ChatMarkdownEditorPage));
        final Uint8List bytes = await tester
            .runAsync(() => state.debugBuildPdfBytesForTest()) as Uint8List;

        expect(bytes, isNotEmpty);
        expect(capturedHtml, isNotNull);
        expect(capturedHtml, contains('data:image/png;base64,'));
        expect(
            capturedHtml, isNot(contains('secondloop://attachment/sha_pdf')));
        expect(backend.readAttachmentBySha256Calls, contains('sha_pdf'));
        expect(backend.readAttachmentBytesCalls, contains('sha_pdf'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'editor export menu copy action resolves persisted attachment images',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final backend = _ExportAttachmentBackend();
      final mockContext =
          superNativeExtensionsContext as MockMessageChannelContext;
      var nextProviderId = 1;
      mockContext.registerMockMethodCallHandler('DataProviderManager', (call) {
        switch (call.method) {
          case 'registerDataProvider':
            return nextProviderId++;
          case 'unregisterDataProvider':
            return null;
          default:
            return null;
        }
      });
      mockContext.registerMockMethodCallHandler('ClipboardWriter', (call) {
        if (call.method == 'writeToClipboard') {
          return null;
        }
        return null;
      });

      try {
        await tester.pumpWidget(_buildEditorApp(
          backend: backend,
          initialText: '![saved](secondloop://attachment/sha_copy)',
        ));
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('chat_markdown_editor_export_menu'))
              .evaluate()
              .isNotEmpty,
        );

        await _triggerExportAction(tester, 'copyToClipboard');
        await _pumpUntil(
          tester,
          () => find.text('Copied to clipboard').evaluate().isNotEmpty,
        );

        expect(find.text('Copied to clipboard'), findsOneWidget);
        expect(backend.readAttachmentBySha256Calls, contains('sha_copy'));
        expect(backend.readAttachmentBytesCalls, contains('sha_copy'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

Widget _buildEditorApp({
  required AppBackend backend,
  required String initialText,
  ChatMarkdownPdfExporter? pdfExporter,
  ChatMarkdownPdfHtmlBuilder? pdfHtmlBuilder,
}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: Scaffold(
            body: ChatMarkdownEditorPage(
              initialText: initialText,
              pdfExporter: pdfExporter,
              pdfHtmlBuilder: pdfHtmlBuilder,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _triggerExportAction(
  WidgetTester tester,
  String actionName,
) async {
  final menuFinder =
      find.byKey(const ValueKey('chat_markdown_editor_export_menu'));
  final context = tester.element(menuFinder);
  final dynamic menuWidget = tester.widget(menuFinder);
  final List<dynamic> entries =
      List<dynamic>.from(menuWidget.itemBuilder(context));
  final dynamic target = switch (actionName) {
    'copyToClipboard' => entries[3],
    _ => entries.firstWhere(
        (entry) => '${entry.value}'.contains(actionName),
      ),
  };
  menuWidget.onSelected(target.value);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxTicks = 100,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < maxTicks; i += 1) {
    if (condition()) return;
    await tester.pump(step);
  }
}

final class _ExportAttachmentBackend extends TestAppBackend
    implements AttachmentsBackend {
  final List<String> readAttachmentBySha256Calls = <String>[];
  final List<String> readAttachmentBytesCalls = <String>[];

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async {
    readAttachmentBySha256Calls.add(attachmentSha256);
    return Attachment(
      sha256: attachmentSha256,
      mimeType: 'image/png',
      path: '$attachmentSha256.png',
      byteLen: _pngBytes().length,
      createdAtMs: 1,
    );
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    readAttachmentBytesCalls.add(sha256);
    return _pngBytes();
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async =>
      const <Attachment>[];

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {}

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async =>
      const <Attachment>[];
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
