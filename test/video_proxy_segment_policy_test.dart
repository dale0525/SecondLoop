import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/media_backup/video_proxy_segment_policy.dart';
import 'package:secondloop/features/media_backup/video_transcode_worker.dart';

void main() {
  test(
      'selectVideoProxySegments keeps all non-empty segments without truncation',
      () {
    final segments = <VideoTranscodeSegment>[
      VideoTranscodeSegment(
        index: 0,
        bytes: Uint8List.fromList(List<int>.filled(3, 1)),
        mimeType: 'video/mp4',
      ),
      VideoTranscodeSegment(
        index: 1,
        bytes: Uint8List.fromList(List<int>.filled(5, 2)),
        mimeType: 'video/x-matroska',
      ),
      VideoTranscodeSegment(
        index: 2,
        bytes: Uint8List(0),
        mimeType: 'video/mp4',
      ),
      VideoTranscodeSegment(
        index: 3,
        bytes: Uint8List.fromList(List<int>.filled(7, 3)),
        mimeType: 'video/webm',
      ),
    ];

    final selected = selectVideoProxySegments(segments);

    expect(
        selected.segments.map((item) => item.index).toList(growable: false), [
      0,
      1,
      3,
    ]);
    expect(selected.totalBytes, 15);
    expect(selected.isTruncated, isFalse);
  });
}
