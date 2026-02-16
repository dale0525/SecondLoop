import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/share/share_ingest_gate.dart';

void main() {
  test('video manifest payload v2 includes video and audio fields', () {
    final payload = buildVideoManifestPayload(
      videoSha256: 'sha_video_proxy',
      videoMimeType: 'video/mp4',
      audioSha256: 'sha_audio',
      audioMimeType: 'audio/mp4',
      segmentCount: 3,
      videoSegments: const [
        (index: 0, sha256: 'sha_seg_0', mimeType: 'video/mp4'),
        (index: 1, sha256: 'sha_seg_1', mimeType: 'video/mp4'),
      ],
    );

    expect(payload['schema'], 'secondloop.video_manifest.v2');
    expect(payload['video_sha256'], 'sha_video_proxy');
    expect(payload['video_mime_type'], 'video/mp4');
    expect(payload['original_sha256'], 'sha_video_proxy');
    expect(payload['original_mime_type'], 'video/mp4');
    expect(payload['audio_sha256'], 'sha_audio');
    expect(payload['audio_mime_type'], 'audio/mp4');
    expect(payload['segment_count'], 3);
    final segments = payload['video_segments'] as List<Object?>;
    expect(segments.length, 2);
    expect(segments.first, {
      'index': 0,
      'sha256': 'sha_seg_0',
      'mime_type': 'video/mp4',
    });
  });

  test('video manifest payload serializes proxy and preview metadata', () {
    final payload = buildVideoManifestPayload(
      videoSha256: 'sha_video_proxy',
      videoMimeType: 'video/mp4',
      videoKind: 'screen_recording',
      videoKindConfidence: 1.4,
      videoProxySha256: 'sha_video_proxy',
      posterSha256: 'sha_poster',
      posterMimeType: 'image/jpeg',
      keyframes: const [
        (
          index: 0,
          sha256: 'sha_keyframe_0',
          mimeType: 'image/jpeg',
          tMs: 1200,
          kind: 'slide',
        ),
      ],
      videoProxyMaxDurationMs: 3,
      videoProxyMaxBytes: 4,
      videoProxyTotalBytes: 5,
      videoProxyTruncated: true,
    );

    expect(payload['video_kind'], 'screen_recording');
    expect(payload['video_kind_confidence'], 1.0);
    expect(payload['video_proxy_sha256'], 'sha_video_proxy');
    expect(payload['poster_sha256'], 'sha_poster');
    expect(payload['poster_mime_type'], 'image/jpeg');
    expect(payload['video_proxy_max_duration_ms'], 3);
    expect(payload['video_proxy_max_bytes'], 4);
    expect(payload['video_proxy_total_bytes'], 5);
    expect(payload['video_proxy_truncated'], isTrue);

    final keyframes = payload['keyframes'] as List<Object?>;
    expect(keyframes, [
      {
        'index': 0,
        'sha256': 'sha_keyframe_0',
        'mime_type': 'image/jpeg',
        't_ms': 1200,
        'kind': 'slide',
      },
    ]);
  });

  test('video manifest payload omits optional media fields when absent', () {
    final payload = buildVideoManifestPayload(
      videoSha256: 'sha_video_proxy',
      videoMimeType: 'video/mp4',
      videoKind: 'invalid_kind',
      videoKindConfidence: -1.0,
    );

    expect(payload['schema'], 'secondloop.video_manifest.v2');
    expect(payload['video_sha256'], 'sha_video_proxy');
    expect(payload['video_mime_type'], 'video/mp4');
    expect(payload['video_kind'], 'unknown');
    expect(payload['video_kind_confidence'], 0.0);
    expect(payload['audio_sha256'], isNull);
    expect(payload['audio_mime_type'], isNull);
    expect(payload.containsKey('video_proxy_sha256'), isFalse);
    expect(payload.containsKey('poster_sha256'), isFalse);
    expect(payload.containsKey('keyframes'), isFalse);
    expect(payload.containsKey('video_proxy_total_bytes'), isFalse);
    expect(payload.containsKey('video_proxy_truncated'), isFalse);
  });

  test('video manifest payload keeps predefined common video kinds', () {
    final payload = buildVideoManifestPayload(
      videoSha256: 'sha_video_proxy',
      videoMimeType: 'video/mp4',
      videoKind: 'meeting',
    );

    expect(payload['video_kind'], 'meeting');
  });
}
