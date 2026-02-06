import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/audio_attachment_player.dart';

void main() {
  test('normalizes audio MIME aliases used by shared files', () {
    expect(normalizeAudioPlaybackMimeType('audio/x-m4a'), 'audio/mp4');
    expect(normalizeAudioPlaybackMimeType('audio/m4a'), 'audio/mp4');
    expect(normalizeAudioPlaybackMimeType('audio/x-wav'), 'audio/wav');
    expect(normalizeAudioPlaybackMimeType('audio/x-mp3'), 'audio/mpeg');
    expect(normalizeAudioPlaybackMimeType(' audio/mp4 '), 'audio/mp4');
  });
}
