import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/share/share_ingest_gate.dart';

void main() {
  test('video manifest payload includes audio fields when provided', () {
    final payload = buildVideoManifestPayload(
      originalSha256: 'sha_orig',
      originalMimeType: 'video/mp4',
      audioSha256: 'sha_audio',
      audioMimeType: 'audio/mp4',
    );

    expect(payload['schema'], 'secondloop.video_manifest.v1');
    expect(payload['original_sha256'], 'sha_orig');
    expect(payload['original_mime_type'], 'video/mp4');
    expect(payload['audio_sha256'], 'sha_audio');
    expect(payload['audio_mime_type'], 'audio/mp4');
  });

  test('video manifest payload omits audio fields when absent', () {
    final payload = buildVideoManifestPayload(
      originalSha256: 'sha_orig',
      originalMimeType: 'video/mp4',
    );

    expect(payload['schema'], 'secondloop.video_manifest.v1');
    expect(payload['audio_sha256'], isNull);
    expect(payload['audio_mime_type'], isNull);
  });
}
