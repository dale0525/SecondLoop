import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  test('fileExtensionForSystemOpenMimeType maps pdf to .pdf', () {
    expect(fileExtensionForSystemOpenMimeType('application/pdf'), '.pdf');
    expect(fileExtensionForSystemOpenMimeType('APPLICATION/PDF'), '.pdf');
    expect(
      fileExtensionForSystemOpenMimeType('application/octet-stream'),
      '.bin',
    );
  });

  test('buildPdfOcrDebugMarker only emits in debug mode', () {
    final hidden = buildPdfOcrDebugMarker(
      isPdf: true,
      debugEnabled: false,
      source: 'ocr',
      autoStatus: 'ok',
      needsOcr: false,
      ocrEngine: 'apple_vision',
      ocrLangHints: 'device_plus_en',
      ocrDpi: 180,
      ocrRetryAttempted: true,
      ocrRetryAttempts: 2,
      ocrRetryHints: 'en,zh_en',
      processedPages: 2,
      pageCount: 2,
    );
    expect(hidden, isNull);

    final shown = buildPdfOcrDebugMarker(
      isPdf: true,
      debugEnabled: true,
      source: 'ocr',
      autoStatus: 'ok',
      needsOcr: false,
      ocrEngine: 'apple_vision',
      ocrLangHints: 'device_plus_en',
      ocrDpi: 180,
      ocrRetryAttempted: true,
      ocrRetryAttempts: 2,
      ocrRetryHints: 'en,zh_en',
      processedPages: 2,
      pageCount: 2,
    );
    expect(shown, contains('debug.ocr'));
    expect(shown, contains('source=ocr'));
  });

  testWidgets('NonImageAttachmentView renders markdown with compact sections',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-url',
      mimeType: 'application/x.secondloop.url+json',
      path: 'attachments/sha-url.bin',
      byteLen: 128,
      createdAtMs: 0,
    );
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': 'secondloop.url_manifest.v1',
          'url': 'https://example.com/p',
        }),
      ),
    );

    final payload = <String, Object?>{
      'title': 'Example Title',
      'canonical_url': 'https://example.com/canonical',
      'readable_text_excerpt': '# Excerpt Heading\n- bullet',
      'readable_text_full': '# Full Heading\n```\nFull body\n```',
      'needs_ocr': false,
    };

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: bytes,
            displayTitle: 'Attachment',
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Example Title'), findsNothing);
    expect(find.text('Original URL'), findsNothing);
    expect(find.text('https://example.com/p'), findsNothing);
    expect(find.text('Canonical URL'), findsNothing);
    expect(find.text('https://example.com/canonical'), findsNothing);
    expect(
      find.byKey(const ValueKey('attachment_non_image_preview_surface')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('attachment_text_summary_display')),
        findsNothing);
    expect(find.byKey(const ValueKey('attachment_text_full_markdown_display')),
        findsOneWidget);
    expect(find.text('Excerpt Heading'), findsNothing);
    expect(find.byKey(const ValueKey('attachment_content_share_button')),
        findsNothing);
    expect(find.byKey(const ValueKey('attachment_content_download_button')),
        findsNothing);
    expect(find.text('Size'), findsNothing);
    expect(find.text('Full text'), findsNothing);
    expect(find.text('Full Heading'), findsOneWidget);
  });

  testWidgets('NonImageAttachmentView shows None when full text is missing',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-empty',
      mimeType: 'application/pdf',
      path: 'attachments/sha-empty.bin',
      byteLen: 128,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            displayTitle: 'PDF attachment',
            initialAnnotationPayload: const <String, Object?>{},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attachment_text_summary_empty')),
        findsNothing);
    expect(find.byKey(const ValueKey('attachment_text_full_empty')),
        findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('NonImageAttachmentView supports manual edit on full only',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-editable',
      mimeType: 'application/pdf',
      path: 'attachments/sha-editable.bin',
      byteLen: 128,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'summary': 'Old summary',
      'full_text': '# Old full',
    };
    String? savedFull;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: NonImageAttachmentView(
              attachment: attachment,
              bytes: Uint8List.fromList(const <int>[1, 2, 3]),
              displayTitle: 'PDF attachment',
              initialAnnotationPayload: payload,
              onSaveFull: (value) async {
                savedFull = value;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attachment_text_summary_edit')),
        findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('attachment_text_full_edit')).first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attachment_text_full_field')).first,
      '## Updated full',
    );
    await tester
        .tap(find.byKey(const ValueKey('attachment_text_full_save')).first);
    await tester.pumpAndSettle();

    expect(savedFull, '## Updated full');
  });

  testWidgets('NonImageAttachmentView reruns OCR via options dialog',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-pdf',
      mimeType: 'application/pdf',
      path: 'attachments/sha-pdf.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'needs_ocr': true,
      'extracted_text_full': '',
      'extracted_text_excerpt': '',
    };
    var runInvoked = 0;
    var selectedHint = 'device_plus_en';

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            displayTitle: 'PDF attachment',
            initialAnnotationPayload: payload,
            onRunOcr: () async {
              runInvoked += 1;
            },
            ocrLanguageHints: selectedHint,
            onOcrLanguageHintsChanged: (next) => selectedHint = next,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('attachment_text_full_regenerate')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_ocr_regenerate_dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment_ocr_language_hint_dialog_field')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('attachment_ocr_language_hint_dialog_field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinese + English').last);
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('attachment_ocr_regenerate_confirm')));
    await tester.pumpAndSettle();

    expect(runInvoked, 1);
    expect(selectedHint, 'zh_en');
  });

  testWidgets('NonImageAttachmentView reruns OCR for video manifest',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-video-manifest',
      mimeType: 'application/x.secondloop.video+json',
      path: 'attachments/sha-video-manifest.bin',
      byteLen: 128,
      createdAtMs: 0,
    );
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': 'secondloop.video_manifest.v1',
          'original_sha256': 'sha-original-video',
          'original_mime_type': 'video/mp4',
        }),
      ),
    );
    var runInvoked = 0;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: bytes,
            displayTitle: 'Video attachment',
            onRunOcr: () async {
              runInvoked += 1;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester
        .tap(find.byKey(const ValueKey('attachment_text_full_regenerate')));
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('attachment_ocr_regenerate_confirm')));
    await tester.pump();

    expect(runInvoked, 1);
  });

  testWidgets('NonImageAttachmentView shows video manifest insight fields',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-video-insights',
      mimeType: 'application/x.secondloop.video+json',
      path: 'attachments/sha-video-insights.bin',
      byteLen: 128,
      createdAtMs: 0,
    );
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': 'secondloop.video_manifest.v2',
          'video_sha256': 'sha-original-video',
          'video_mime_type': 'video/mp4',
          'video_segments': [
            {
              'index': 0,
              'sha256': 'sha-seg-1',
              'mime_type': 'video/mp4',
            },
          ],
        }),
      ),
    );
    final payload = <String, Object?>{
      'video_content_kind': 'knowledge',
      'video_summary': 'This lesson explains OCR fallbacks.',
      'knowledge_markdown_excerpt': '## Steps\n1. Try multimodal\n2. Fallback',
      'readable_text_full': '## Steps\n1. Try multimodal\n2. Fallback',
      'readable_text_excerpt': 'This lesson explains OCR fallbacks.',
    };

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: bytes,
            displayTitle: 'Video attachment',
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('video_manifest_insights_surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('video_manifest_content_kind_value')),
      findsOneWidget,
    );
    expect(find.text('Knowledge video'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('video_manifest_summary_text')),
      findsOneWidget,
    );
    expect(find.text('This lesson explains OCR fallbacks.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('video_manifest_detail_text')),
      findsOneWidget,
    );
    expect(find.textContaining('Try multimodal'), findsWidgets);
  });

  testWidgets('NonImageAttachmentView localizes video insight labels in zh_CN',
      (tester) async {
    final previousLocale = LocaleSettings.currentLocale;
    addTearDown(() {
      LocaleSettings.setLocale(previousLocale);
    });
    LocaleSettings.setLocale(AppLocale.zhCn);

    const attachment = Attachment(
      sha256: 'sha-video-insights-zh',
      mimeType: 'application/x.secondloop.video+json',
      path: 'attachments/sha-video-insights-zh.bin',
      byteLen: 128,
      createdAtMs: 0,
    );
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': 'secondloop.video_manifest.v2',
          'video_sha256': 'sha-original-video',
          'video_mime_type': 'video/mp4',
          'video_segments': [
            {
              'index': 0,
              'sha256': 'sha-seg-1',
              'mime_type': 'video/mp4',
            },
          ],
        }),
      ),
    );
    final payload = <String, Object?>{
      'video_content_kind': 'knowledge',
      'video_summary': '这是一个知识类视频概要。',
      'knowledge_markdown_excerpt': '## 要点\n1. 多模态优先\n2. 本地回退',
      'readable_text_full': '## 要点\n1. 多模态优先\n2. 本地回退',
    };

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: bytes,
            displayTitle: '视频附件',
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('知识类视频'), findsOneWidget);
    expect(find.text('内容类型'), findsOneWidget);
    expect(find.text('视频概要'), findsOneWidget);
    expect(find.text('知识文稿'), findsOneWidget);
  });

  testWidgets('NonImageAttachmentView disables regenerate action while running',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-pdf-running',
      mimeType: 'application/pdf',
      path: 'attachments/sha-pdf-running.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'needs_ocr': false,
      'ocr_text_excerpt': 'ready',
    };

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            displayTitle: 'PDF attachment',
            initialAnnotationPayload: payload,
            onRunOcr: () async {},
            ocrRunning: true,
          ),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('attachment_text_full_regenerate')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'NonImageAttachmentView prefers OCR text when extracted looks degraded',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-pdf-degraded',
      mimeType: 'application/pdf',
      path: 'attachments/sha-pdf-degraded.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'needs_ocr': false,
      'extracted_text_excerpt': 'A B C D E F G H I J K L M N O P',
      'ocr_text_excerpt': 'Invoice total is 123.45 USD.',
      'ocr_engine': 'apple_vision',
    };

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            displayTitle: 'PDF attachment',
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Invoice total is 123.45 USD.'), findsOneWidget);
    expect(find.text('A B C D E F G H I J K L M N O P'), findsNothing);
  });

  testWidgets('NonImageAttachmentView supports legacy image ocr_text field',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-pdf-legacy-ocr',
      mimeType: 'application/pdf',
      path: 'attachments/sha-pdf-legacy-ocr.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'needs_ocr': false,
      'ocr_text': '[page 1]\nLegacy OCR line one\nLegacy OCR line two',
    };

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            displayTitle: 'PDF attachment',
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Legacy OCR line one'), findsWidgets);
    expect(find.textContaining('Legacy OCR line two'), findsWidgets);
  });

  testWidgets('NonImageAttachmentView shows PDF OCR debug marker',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-pdf-debug',
      mimeType: 'application/pdf',
      path: 'attachments/sha-pdf-debug.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'needs_ocr': false,
      'page_count': 2,
      'ocr_processed_pages': 0,
      'extracted_text_excerpt': 'Plain extracted text',
    };

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            displayTitle: 'PDF attachment',
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('source=extracted'), findsOneWidget);
    expect(find.textContaining('hints=none'), findsOneWidget);
  });

  testWidgets(
      'NonImageAttachmentView does not show preparing when OCR finished with no text',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-pdf-empty-ocr',
      mimeType: 'application/pdf',
      path: 'attachments/sha-pdf-empty-ocr.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'needs_ocr': false,
      'ocr_auto_status': 'ok',
      'ocr_engine': 'apple_vision',
      'ocr_page_count': 3,
      'ocr_processed_pages': 3,
      'ocr_text_excerpt': '',
      'ocr_text_full': '',
      'extracted_text_excerpt': '',
      'extracted_text_full': '',
    };

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            displayTitle: 'PDF attachment',
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Preparing semantic search…'), findsNothing);
    expect(find.text('Preview unavailable'), findsNothing);
  });
}
