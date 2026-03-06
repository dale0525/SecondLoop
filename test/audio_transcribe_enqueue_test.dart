import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_enqueue.dart';

final class _CaptureNativeBackend implements NativeAppBackend {
  final List<({String attachmentSha256, String lang, int nowMs})> enqueueCalls =
      <({String attachmentSha256, String lang, int nowMs})>[];

  @override
  Future<void> enqueueAttachmentAnnotation(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    enqueueCalls.add((
      attachmentSha256: attachmentSha256,
      lang: lang,
      nowMs: nowMs,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('candidate mime type matches audio and video only', () {
    expect(isAudioTranscribeCandidateMimeType('audio/wav'), isTrue);
    expect(isAudioTranscribeCandidateMimeType('video/mp4'), isTrue);
    expect(isAudioTranscribeCandidateMimeType('image/png'), isFalse);
    expect(isAudioTranscribeCandidateMimeType('text/plain'), isFalse);
  });

  test('maybeEnqueueAudioTranscribe enqueues with und language', () async {
    final backend = _CaptureNativeBackend();

    await maybeEnqueueAudioTranscribe(
      backend: backend,
      sessionKey: Uint8List(32),
      attachmentSha256: 'sha-123',
      mimeType: 'audio/mpeg',
      lang: '',
      respectFeatureToggle: false,
      nowMs: 123,
    );

    expect(backend.enqueueCalls, hasLength(1));
    expect(backend.enqueueCalls.first.attachmentSha256, 'sha-123');
    expect(backend.enqueueCalls.first.lang, 'und');
    expect(backend.enqueueCalls.first.nowMs, 123);
  });

  test('maybeEnqueueAudioTranscribe prepares cloud route before enqueue',
      () async {
    final backend = _CaptureNativeBackend();
    var prepareCalls = 0;

    await maybeEnqueueAudioTranscribe(
      backend: backend,
      sessionKey: Uint8List(32),
      attachmentSha256: 'sha-123',
      mimeType: 'audio/mpeg',
      respectFeatureToggle: false,
      nowMs: 123,
      beforeEnqueue: () async {
        prepareCalls += 1;
      },
    );

    expect(prepareCalls, 1);
    expect(backend.enqueueCalls, hasLength(1));
  });

  test('maybeEnqueueAudioTranscribe skips non-media mime types', () async {
    final backend = _CaptureNativeBackend();

    await maybeEnqueueAudioTranscribe(
      backend: backend,
      sessionKey: Uint8List(32),
      attachmentSha256: 'sha-123',
      mimeType: 'image/png',
      respectFeatureToggle: false,
      nowMs: 123,
    );

    expect(backend.enqueueCalls, isEmpty);
  });
}
