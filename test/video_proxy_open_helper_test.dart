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

  test('extensionForVideoMimeType supports common video formats', () {
    expect(extensionForVideoMimeType('video/mp4'), '.mp4');
    expect(extensionForVideoMimeType('video/quicktime'), '.mov');
    expect(extensionForVideoMimeType('video/x-matroska'), '.mkv');
    expect(extensionForVideoMimeType('video/x-msvideo'), '.avi');
    expect(extensionForVideoMimeType('video/x-ms-wmv'), '.wmv');
    expect(extensionForVideoMimeType('video/x-ms-asf'), '.asf');
    expect(extensionForVideoMimeType('video/x-flv'), '.flv');
    expect(extensionForVideoMimeType('video/mpeg'), '.mpeg');
    expect(extensionForVideoMimeType('video/mp2t'), '.ts');
    expect(extensionForVideoMimeType('video/3gpp'), '.3gp');
    expect(extensionForVideoMimeType('video/3gpp2'), '.3g2');
    expect(extensionForVideoMimeType('video/ogg'), '.ogv');
  });
}
