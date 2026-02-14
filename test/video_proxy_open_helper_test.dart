import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/video_proxy_open_helper.dart';

void main() {
  test('resolveVideoProxySegments falls back to primary segment', () {
    final segments = resolveVideoProxySegments(
      primarySha256: 'sha-primary',
      primaryMimeType: 'video/mp4',
      segmentRefs: null,
    );

    expect(segments.length, 1);
    expect(segments.first.sha256, 'sha-primary');
    expect(segments.first.mimeType, 'video/mp4');
  });

  test('resolveVideoProxySegments keeps order and removes duplicate shas', () {
    final segments = resolveVideoProxySegments(
      primarySha256: 'sha-primary',
      primaryMimeType: 'video/mp4',
      segmentRefs: const <({String sha256, String mimeType})>[
        (sha256: 'sha-primary', mimeType: 'video/mp4'),
        (sha256: 'sha-seg-1', mimeType: 'video/mp4'),
        (sha256: 'sha-seg-1', mimeType: 'video/mp4'),
        (sha256: ' ', mimeType: 'video/mp4'),
        (sha256: 'sha-seg-2', mimeType: 'video/mp4'),
      ],
    );

    expect(segments.map((item) => item.sha256).toList(growable: false), [
      'sha-primary',
      'sha-seg-1',
      'sha-seg-2',
    ]);
  });
}
