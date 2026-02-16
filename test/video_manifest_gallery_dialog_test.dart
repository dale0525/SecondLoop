import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/video_manifest_gallery_dialog.dart';

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
}
