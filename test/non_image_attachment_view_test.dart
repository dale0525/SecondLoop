import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('NonImageAttachmentView shows URL fields and excerpt',
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
      'readable_text_excerpt': 'Excerpt line',
      'readable_text_full': 'Excerpt line\nFull body',
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
    expect(find.text('Excerpt'), findsOneWidget);
    expect(find.text('Excerpt line'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_outlined), findsOneWidget);
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

    expect(find.text('OCR required'), findsOneWidget);
    expect(
      find.text('This PDF appears to contain no selectable text.'),
      findsOneWidget,
    );
  });
}
