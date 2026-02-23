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

    expect(payload.containsKey('video_kind'), isFalse);
    expect(payload.containsKey('video_kind_confidence'), isFalse);
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

  test('initial video extract payload seeds auto OCR and transcript linkage',
      () {
    final payload = buildInitialVideoExtractPayload(
      manifestMimeType: 'application/x.secondloop.video+json',
      originalSha256: 'sha_video_proxy',
      originalMimeType: 'video/mp4',
      audioSha256: 'sha_audio_proxy',
      audioMimeType: 'audio/mp4',
      segmentCount: 2,
    );

    expect(payload['schema'], 'secondloop.video_extract.v1');
    expect(payload['mime_type'], 'application/x.secondloop.video+json');
    expect(payload['original_sha256'], 'sha_video_proxy');
    expect(payload['audio_sha256'], 'sha_audio_proxy');
    expect(payload['audio_mime_type'], 'audio/mp4');
    expect(payload['video_segment_count'], 2);
    expect(payload['video_processed_segment_count'], 0);
    expect(payload['needs_ocr'], isTrue);
    expect(payload['ocr_auto_status'], 'queued');
  });
  test('video manifest payload omits optional media fields when absent', () {
    final payload = buildVideoManifestPayload(
      videoSha256: 'sha_video_proxy',
      videoMimeType: 'video/mp4',
    );

    expect(payload['schema'], 'secondloop.video_manifest.v2');
    expect(payload['video_sha256'], 'sha_video_proxy');
    expect(payload['video_mime_type'], 'video/mp4');
    expect(payload.containsKey('video_kind'), isFalse);
    expect(payload.containsKey('video_kind_confidence'), isFalse);
    expect(payload['audio_sha256'], isNull);
    expect(payload['audio_mime_type'], isNull);
    expect(payload.containsKey('video_proxy_sha256'), isFalse);
    expect(payload.containsKey('poster_sha256'), isFalse);
    expect(payload.containsKey('keyframes'), isFalse);
    expect(payload.containsKey('video_proxy_total_bytes'), isFalse);
    expect(payload.containsKey('video_proxy_truncated'), isFalse);
  });
}
