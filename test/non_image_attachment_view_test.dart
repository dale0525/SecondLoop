import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  test('fileExtensionForSystemOpenMimeType maps pdf to .pdf', () {
    expect(fileExtensionForSystemOpenMimeType('application/pdf'), '.pdf');
    expect(fileExtensionForSystemOpenMimeType('APPLICATION/PDF'), '.pdf');
    expect(
        fileExtensionForSystemOpenMimeType('application/octet-stream'), '.bin');
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

  testWidgets('NonImageAttachmentView renders markdown and action buttons',
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
        const MaterialApp(
          home: Scaffold(),
        ),
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: bytes,
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Example Title'), findsOneWidget);
    expect(find.text('Original URL'), findsOneWidget);
    expect(find.text('https://example.com/p'), findsOneWidget);
    expect(find.text('Canonical URL'), findsOneWidget);
    expect(find.text('https://example.com/canonical'), findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_content_tab_summary')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_content_tab_full')),
        findsOneWidget);
    expect(find.text('Excerpt Heading'), findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_content_share_button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_content_download_button')),
        findsOneWidget);

    await tester.tap(find.text('Full text'));
    await tester.pumpAndSettle();
    expect(find.text('Full Heading'), findsOneWidget);
  });

  testWidgets('NonImageAttachmentView shows OCR required for textless PDF',
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

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            initialAnnotationPayload: payload,
            onRunOcr: () async {
              runInvoked += 1;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OCR required'), findsOneWidget);
    expect(
      find.text('This PDF appears to contain no selectable text.'),
      findsOneWidget,
    );
    expect(find.text('Run OCR'), findsOneWidget);

    await tester.ensureVisible(find.text('Run OCR'));
    await tester.tap(find.text('Run OCR'));
    await tester.pump();
    expect(runInvoked, 1);
  });

  testWidgets('NonImageAttachmentView shows Run OCR for video manifest',
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
            onRunOcr: () async {
              runInvoked += 1;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Run OCR'), findsOneWidget);
    await tester.ensureVisible(find.text('Run OCR'));
    await tester.tap(find.text('Run OCR'));
    await tester.pump();
    expect(runInvoked, 1);
  });

  testWidgets('NonImageAttachmentView shows Re-run OCR after OCR is ready',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-pdf-ready',
      mimeType: 'application/pdf',
      path: 'attachments/sha-pdf-ready.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'needs_ocr': false,
      'extracted_text_excerpt': 'Already extracted',
      'ocr_text_excerpt': 'OCR fallback',
    };
    var runInvoked = 0;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            initialAnnotationPayload: payload,
            onRunOcr: () async {
              runInvoked += 1;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OCR required'), findsNothing);
    expect(find.text('Re-run OCR'), findsOneWidget);
    expect(find.text('Already extracted'), findsOneWidget);

    await tester.ensureVisible(find.text('Re-run OCR'));
    await tester.tap(find.text('Re-run OCR'));
    await tester.pump();
    expect(runInvoked, 1);
  });

  testWidgets('NonImageAttachmentView lets user change OCR language hint',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-pdf-lang',
      mimeType: 'application/pdf',
      path: 'attachments/sha-pdf-lang.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
    final payload = <String, Object?>{
      'needs_ocr': true,
      'extracted_text_excerpt': '',
    };
    var selectedHint = 'device_plus_en';

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: Uint8List.fromList(const <int>[1, 2, 3]),
            initialAnnotationPayload: payload,
            onRunOcr: () async {},
            ocrLanguageHints: selectedHint,
            onOcrLanguageHintsChanged: (next) => selectedHint = next,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_ocr_language_hint_field')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('attachment_ocr_language_hint_field')),
    );
    await tester.tap(
      find.byKey(const ValueKey('attachment_ocr_language_hint_field')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Chinese + English').last);
    await tester.tap(find.text('Chinese + English').last);
    await tester.pumpAndSettle();

    expect(selectedHint, 'zh_en');
  });

  testWidgets('NonImageAttachmentView disables OCR action while running',
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
            initialAnnotationPayload: payload,
            onRunOcr: () async {},
            ocrRunning: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OCR in progress…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('attachment_run_ocr_button')),
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
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Invoice total is 123.45 USD.'), findsOneWidget);
    expect(find.text('A B C D E F G H I J K L M N O P'), findsNothing);
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
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('pdf_ocr_debug_marker')), findsOneWidget);
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
            initialAnnotationPayload: payload,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Preparing semantic search…'), findsNothing);
    expect(find.byKey(const ValueKey('attachment_no_text_status')),
        findsOneWidget);
    expect(find.text('OCR failed on this device.'), findsOneWidget);
  });
}
