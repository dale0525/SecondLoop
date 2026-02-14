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

  test('video manifest payload omits optional audio fields when absent', () {
    final payload = buildVideoManifestPayload(
      videoSha256: 'sha_video_proxy',
      videoMimeType: 'video/mp4',
    );

    expect(payload['schema'], 'secondloop.video_manifest.v2');
    expect(payload['video_sha256'], 'sha_video_proxy');
    expect(payload['video_mime_type'], 'video/mp4');
    expect(payload['audio_sha256'], isNull);
    expect(payload['audio_mime_type'], isNull);
  });
}
