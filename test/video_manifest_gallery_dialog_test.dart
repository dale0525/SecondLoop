import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/video_attachment_inline_player.dart';
import 'package:secondloop/features/attachments/video_attachment_player_page.dart';
import 'package:secondloop/features/attachments/video_manifest_gallery_dialog.dart';
import 'package:secondloop/features/attachments/video_proxy_open_helper.dart';

void main() {
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6Xgm1sAAAAASUVORK5CYII=',
  );

  Future<void> openGallery(
    WidgetTester tester, {
    required List<VideoManifestGalleryEntry> entries,
    int initialIndex = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                key: const ValueKey('open_gallery_button'),
                onPressed: () {
                  showVideoManifestGalleryDialog(
                    context,
                    entries: entries,
                    initialIndex: initialIndex,
                    loadBytes: (_) async => onePixelPng,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_gallery_button')));
    await tester.pumpAndSettle();
  }

  String currentIndexLabel(WidgetTester tester) {
    final indexText = tester.widget<Text>(
      find.byKey(const ValueKey('video_manifest_gallery_index_indicator')),
    );
    return indexText.data ?? '';
  }

  testWidgets('VideoManifestGalleryDialog loops with prev and next buttons',
      (tester) async {
    await openGallery(
      tester,
      entries: const <VideoManifestGalleryEntry>[
        VideoManifestGalleryEntry.keyframe(keyframeSha256: 'sha-keyframe-1'),
        VideoManifestGalleryEntry.keyframe(keyframeSha256: 'sha-keyframe-2'),
        VideoManifestGalleryEntry.keyframe(keyframeSha256: 'sha-keyframe-3'),
      ],
      initialIndex: 0,
    );

    expect(
      find.byKey(const ValueKey('video_manifest_gallery_prev_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('video_manifest_gallery_next_button')),
      findsOneWidget,
    );
    expect(currentIndexLabel(tester), '1/3');

    await tester
        .tap(find.byKey(const ValueKey('video_manifest_gallery_prev_button')));
    await tester.pumpAndSettle();
    expect(currentIndexLabel(tester), '3/3');

    await tester
        .tap(find.byKey(const ValueKey('video_manifest_gallery_next_button')));
    await tester.pumpAndSettle();
    expect(currentIndexLabel(tester), '1/3');
  });

  testWidgets(
      'VideoManifestGalleryDialog shows a spinner while proxy playback is preparing',
      (tester) async {
    final delayedPlayback = Future<PreparedVideoProxyPlayback>.delayed(
      const Duration(seconds: 1),
      () => const PreparedVideoProxyPlayback(
        segmentFiles: <VideoAttachmentPlayerSegment>[
          VideoAttachmentPlayerSegment(
            filePath: '/tmp/secondloop_missing_inline_video_0.mp4',
            sha256: 'sha-video-0',
            mimeType: 'video/mp4',
          ),
        ],
        initialSegmentIndex: 0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                key: const ValueKey('open_gallery_button'),
                onPressed: () {
                  showVideoManifestGalleryDialog(
                    context,
                    entries: <VideoManifestGalleryEntry>[
                      VideoManifestGalleryEntry.proxy(
                        playbackFuture: delayedPlayback,
                        posterSha256: null,
                      ),
                    ],
                    initialIndex: 0,
                    loadBytes: (_) async => onePixelPng,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_gallery_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(VideoAttachmentInlinePlayer), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(VideoAttachmentInlinePlayer), findsOneWidget);
  });
}
