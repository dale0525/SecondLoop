import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/attachment_processing_status.dart';

void main() {
  test('video payload without transcript waits for speech recognition', () {
    final stage = resolveAttachmentProcessingStage(
      mimeType: 'application/x.secondloop.video+json',
      jobStatus: null,
      payload: const <String, Object?>{
        'schema': 'secondloop.video_extract.v1',
        'ocr_auto_status': 'queued',
        'audio_sha256': 'sha_audio',
        'transcript_full': '',
        'transcript_excerpt': '',
      },
    );

    expect(stage, AttachmentProcessingStage.waitingForSpeechRecognition);
  });

  test(
      'video payload with transcript and running auto OCR understands keyframes',
      () {
    final stage = resolveAttachmentProcessingStage(
      mimeType: 'application/x.secondloop.video+json',
      jobStatus: null,
      payload: const <String, Object?>{
        'schema': 'secondloop.video_extract.v1',
        'ocr_auto_status': 'running',
        'transcript_excerpt': 'hello world',
      },
    );

    expect(stage, AttachmentProcessingStage.understandingKeyframes);
  });

  test('audio pending job maps to transcribing audio', () {
    final stage = resolveAttachmentProcessingStage(
      mimeType: 'audio/mp4',
      jobStatus: 'pending',
      payload: null,
    );

    expect(stage, AttachmentProcessingStage.transcribingAudio);
  });

  test('pdf queued OCR maps to recognizing text', () {
    final stage = resolveAttachmentProcessingStage(
      mimeType: 'application/pdf',
      jobStatus: null,
      payload: const <String, Object?>{
        'ocr_auto_status': 'queued',
        'needs_ocr': true,
      },
    );

    expect(stage, AttachmentProcessingStage.recognizingText);
  });

  test('pdf pending job without payload still maps to recognizing text', () {
    final stage = resolveAttachmentProcessingStage(
      mimeType: 'application/pdf',
      jobStatus: 'pending',
      payload: null,
    );

    expect(stage, AttachmentProcessingStage.recognizingText);
  });

  test('image pending job maps to analyzing image', () {
    final stage = resolveAttachmentProcessingStage(
      mimeType: 'image/jpeg',
      jobStatus: 'pending',
      payload: null,
    );

    expect(stage, AttachmentProcessingStage.analyzingImage);
  });
}
