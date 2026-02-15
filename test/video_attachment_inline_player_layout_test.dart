import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/video_attachment_inline_player.dart';
import 'package:secondloop/features/attachments/video_attachment_player_page.dart';
import 'package:secondloop/features/attachments/video_proxy_open_helper.dart';

void main() {
  testWidgets('VideoAttachmentInlinePlayer avoids overflow in short viewport',
      (tester) async {
    const playback = PreparedVideoProxyPlayback(
      segmentFiles: <VideoAttachmentPlayerSegment>[
        VideoAttachmentPlayerSegment(
          filePath: '/tmp/secondloop_missing_inline_video_0.mp4',
          sha256: 'sha-video-0',
          mimeType: 'video/mp4',
        ),
        VideoAttachmentPlayerSegment(
          filePath: '/tmp/secondloop_missing_inline_video_1.mp4',
          sha256: 'sha-video-1',
          mimeType: 'video/mp4',
        ),
      ],
      initialSegmentIndex: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 752,
              height: 428,
              child: VideoAttachmentInlinePlayer(playback: playback),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('video_inline_player_segment_selector')),
      findsOneWidget,
    );
  });
}
