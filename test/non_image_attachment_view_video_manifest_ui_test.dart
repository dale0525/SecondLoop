import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  Attachment buildVideoManifestAttachment(String sha) {
    return Attachment(
      sha256: sha,
      mimeType: 'application/x.secondloop.video+json',
      path: 'attachments/$sha.bin',
      byteLen: 256,
      createdAtMs: 0,
    );
  }

  Uint8List buildManifestBytes({
    required int keyframeCount,
    int segmentCount = 1,
    bool includeAudio = false,
  }) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': 'secondloop.video_manifest.v2',
          'video_sha256': 'sha-video-proxy',
          'video_mime_type': 'video/mp4',
          'video_proxy_sha256': 'sha-video-proxy',
          if (includeAudio) 'audio_sha256': 'sha-audio',
          if (includeAudio) 'audio_mime_type': 'audio/mp4',
          'poster_sha256': 'sha-poster',
          'poster_mime_type': 'image/jpeg',
          'keyframes': [
            for (var i = 0; i < keyframeCount; i++)
              {
                'index': i,
                'sha256': 'sha-kf-$i',
                'mime_type': 'image/jpeg',
                't_ms': i * 4000,
                'kind': 'scene',
              },
          ],
          'video_segments': [
            for (var i = 0; i < segmentCount; i++)
              {
                'index': i,
                'sha256': 'sha-video-proxy-$i',
                'mime_type': 'video/mp4',
              },
          ],
        }),
      ),
    );
  }

  testWidgets(
      'video manifest preview hides segment/keyframe stats and keeps horizontal scrollbar',
      (tester) async {
    final attachment = buildVideoManifestAttachment('sha-video-preview-ui');
    final bytes = buildManifestBytes(keyframeCount: 10);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: bytes,
            displayTitle: 'Video preview',
            initialAnnotationPayload: const <String, Object?>{},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('video_manifest_preview_surface')),
      findsOneWidget,
    );
    expect(find.textContaining('segments:'), findsNothing);
    expect(find.textContaining('keyframes:'), findsNothing);
    expect(
      find.byKey(const ValueKey('video_manifest_preview_scrollbar')),
      findsOneWidget,
    );

    final scrollFinder =
        find.byKey(const ValueKey('video_manifest_preview_scroll'));
    final scroll = tester.widget<SingleChildScrollView>(scrollFinder);
    expect(scroll.scrollDirection, Axis.horizontal);
  });

  testWidgets(
      'video manifest detail shows aggregate summary and hides legacy insight card',
      (tester) async {
    final attachment = buildVideoManifestAttachment('sha-video-no-insights');
    final bytes = buildManifestBytes(
      keyframeCount: 2,
      segmentCount: 3,
      includeAudio: true,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: bytes,
            displayTitle: 'Video detail',
            initialAnnotationPayload: const <String, Object?>{
              'video_content_kind': 'knowledge',
              'knowledge_markdown_excerpt': '## Key points\n1. OCR fallback',
              'readable_text_full': '## Key points\n1. OCR fallback',
              'video_proxy_truncated': true,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('video_manifest_insights_surface')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('video_manifest_summary_surface')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('video_manifest_summary_segments')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('video_manifest_summary_keyframes')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('video_manifest_summary_audio')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('video_manifest_summary_truncated')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Key points'), findsWidgets);
  });

  testWidgets('video manifest keyframe gallery shows OCR overlay text',
      (tester) async {
    final attachment = buildVideoManifestAttachment('sha-video-keyframe-ocr');
    final bytes = buildManifestBytes(keyframeCount: 2);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: NonImageAttachmentView(
            attachment: attachment,
            bytes: bytes,
            displayTitle: 'Video detail',
            initialAnnotationPayload: const <String, Object?>{
              'ocr_keyframe_texts': [
                {
                  'sha256': 'sha-kf-0',
                  'text': 'Slide title: Local OCR insight',
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('video_manifest_keyframe_preview_0')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('video_manifest_gallery_keyframe_ocr_surface')),
      findsOneWidget,
    );
    expect(find.textContaining('Local OCR insight'), findsOneWidget);
  });
}
