import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/attachment_annotation_job_status_row.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'AttachmentAnnotationJobStatusRow shows audio-specific pending label',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'audio-pending',
      status: 'pending',
      lang: 'en',
      modelName: null,
      attempts: 0,
      nextRetryAtMs: null,
      lastError: null,
      createdAtMs: now - 2000,
      updatedAtMs: now - 2000,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
              mimeType: 'audio/mp4',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Transcribing audio…'), findsOneWidget);
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows recognizing text for pending documents without payload',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'pdf-pending',
      status: 'pending',
      lang: 'en',
      modelName: null,
      attempts: 0,
      nextRetryAtMs: null,
      lastError: null,
      createdAtMs: now - 2000,
      updatedAtMs: now - 2000,
    );

    await tester.pumpWidget(
      _wrapWithBackend(
        backend: _PayloadBackend(annotationPayloadJsonBySha: const {}),
        child: MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
              mimeType: 'application/pdf',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Recognizing text…'), findsOneWidget);
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow does not reload payload on theme-only dependency changes',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'payload-stable',
      status: 'pending',
      lang: 'en',
      modelName: null,
      attempts: 0,
      nextRetryAtMs: null,
      lastError: null,
      createdAtMs: now - 2000,
      updatedAtMs: now - 2000,
    );
    final backend = _PayloadBackend(
      annotationPayloadJsonBySha: const {
        'payload-stable':
            '{"schema":"secondloop.video_extract.v1","ocr_auto_status":"queued","audio_sha256":"sha_audio","transcript_full":"","transcript_excerpt":""}',
      },
    );

    Widget buildApp(ThemeData theme) {
      return _wrapWithBackend(
        backend: backend,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
              mimeType: 'application/x.secondloop.video+json',
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildApp(ThemeData.light()));
    await tester.pump();
    expect(backend.payloadReadCount, 1);

    await tester.pumpWidget(buildApp(ThemeData.dark()));
    await tester.pump();
    expect(backend.payloadReadCount, 1);
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow uses payload to show video-specific pending stage',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'video-pending',
      status: 'pending',
      lang: 'en',
      modelName: null,
      attempts: 0,
      nextRetryAtMs: null,
      lastError: null,
      createdAtMs: now - 2000,
      updatedAtMs: now - 2000,
    );

    await tester.pumpWidget(
      _wrapWithBackend(
        backend: _PayloadBackend(
          annotationPayloadJsonBySha: const {
            'video-pending':
                '{"schema":"secondloop.video_extract.v1","ocr_auto_status":"queued","audio_sha256":"sha_audio","transcript_full":"","transcript_excerpt":""}',
          },
        ),
        child: MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
              mimeType: 'application/x.secondloop.video+json',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Waiting for speech recognition…'), findsOneWidget);
  });

  testWidgets('AttachmentAnnotationJobStatusRow shows running after soft delay',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAtMs = now + const Duration(hours: 1).inMilliseconds;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'abc',
      status: 'pending',
      lang: 'en',
      modelName: null,
      attempts: 0,
      nextRetryAtMs: null,
      lastError: null,
      createdAtMs: createdAtMs,
      updatedAtMs: createdAtMs,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(hours: 2));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows mobile stay-open reminder while pending on mobile',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final job = AttachmentAnnotationJob(
        attachmentSha256: 'mobile-hint',
        status: 'pending',
        lang: 'en',
        modelName: null,
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        createdAtMs: now - 2000,
        updatedAtMs: now - 2000,
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: Scaffold(
              body: AttachmentAnnotationJobStatusRow(
                job: job,
                annotateEnabled: true,
                canAnnotateNow: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('AI analyzing…'), findsOneWidget);
      expect(
        find.text(
          'Keep the app open while AI analyzes. Leaving may interrupt analysis.',
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows install speech pack action on Windows missing recognizer error',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final job = AttachmentAnnotationJob(
        attachmentSha256: 'def',
        status: 'failed',
        lang: 'en',
        modelName: 'windows_native_stt',
        attempts: 1,
        nextRetryAtMs: null,
        lastError:
            'Bad state: audio_transcribe_native_stt_failed:speech_recognizer_unavailable',
        createdAtMs: now,
        updatedAtMs: now,
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: Scaffold(
              body: AttachmentAnnotationJobStatusRow(
                job: job,
                annotateEnabled: true,
                canAnnotateNow: true,
                onInstallSpeechPack: () async {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Install speech pack'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows install action when recognizer probe reports missing on Windows native stt failure',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final job = AttachmentAnnotationJob(
        attachmentSha256: 'ghi',
        status: 'failed',
        lang: 'en',
        modelName: 'windows_native_stt',
        attempts: 1,
        nextRetryAtMs: null,
        lastError: 'Bad state: audio_transcribe_native_stt_failed:unknown',
        createdAtMs: now,
        updatedAtMs: now,
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: Scaffold(
              body: AttachmentAnnotationJobStatusRow(
                job: job,
                annotateEnabled: true,
                canAnnotateNow: true,
                onInstallSpeechPack: () async {},
                windowsSpeechRecognizerProbe: () async => false,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Install speech pack'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows error details action on failed jobs with last error',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'xyz',
      status: 'failed',
      lang: 'en',
      modelName: null,
      attempts: 1,
      nextRetryAtMs: null,
      lastError: 'audio_transcribe_native_stt_failed:test',
      createdAtMs: now,
      updatedAtMs: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
              onRetry: () async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows runtime download action when local capability is missing',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var openDownloadCalls = 0;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'runtime-missing',
      status: 'failed',
      lang: 'en',
      modelName: 'runtime-whisper-tiny',
      attempts: 1,
      nextRetryAtMs: null,
      lastError: 'audio_transcribe_local_runtime_model_missing:tiny',
      createdAtMs: now,
      updatedAtMs: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
              onOpenLocalCapabilityDownload: () async {
                openDownloadCalls += 1;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Download runtime'), findsOneWidget);
    expect(
      find.text(
        'Local capability runtime is missing. Download it to transcribe.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Download runtime'));
    await tester.pump();

    expect(openDownloadCalls, 1);
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows payload too large hint for audio transcribe failures',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'oversized',
      status: 'failed',
      lang: 'en',
      modelName: 'base',
      attempts: 1,
      nextRetryAtMs: null,
      lastError: 'audio_transcribe_http_413:{"error":"payload_too_large"}',
      createdAtMs: now,
      updatedAtMs: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Audio file is too large. Compress or split it and try again.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows model not allowed hint for audio transcribe failures',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'model-not-allowed',
      status: 'failed',
      lang: 'en',
      modelName: 'base',
      attempts: 1,
      nextRetryAtMs: null,
      lastError: 'audio_transcribe_http_400:{"error":"model_not_allowed"}',
      createdAtMs: now,
      updatedAtMs: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'This model is not allowed for audio transcription. Change model or engine in settings.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow shows invalid multipart hint for audio transcribe failures',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'invalid-multipart',
      status: 'failed',
      lang: 'en',
      modelName: 'base',
      attempts: 1,
      nextRetryAtMs: null,
      lastError: 'audio_transcribe_http_400:{"error":"invalid_multipart"}',
      createdAtMs: now,
      updatedAtMs: now,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: true,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Audio request format is invalid. Retry or update the app.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'AttachmentAnnotationJobStatusRow uses provided setup label when capability is unavailable',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'setup-audio',
      status: 'pending',
      lang: 'en',
      modelName: null,
      attempts: 0,
      nextRetryAtMs: null,
      lastError: null,
      createdAtMs: now - 2000,
      updatedAtMs: now - 2000,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AttachmentAnnotationJobStatusRow(
              job: job,
              annotateEnabled: true,
              canAnnotateNow: false,
              setupRequiredLabel: 'Audio transcription needs setup',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Audio transcription needs setup'), findsOneWidget);
    expect(find.text('Image annotations need setup'), findsNothing);
  });
}

Widget _wrapWithBackend({
  required NativeAppBackend backend,
  required Widget child,
}) {
  return wrapWithI18n(
    AppBackendScope(
      backend: backend,
      child: SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: child,
      ),
    ),
  );
}

final class _PayloadBackend extends NativeAppBackend {
  _PayloadBackend({required Map<String, String?> annotationPayloadJsonBySha})
      : _annotationPayloadJsonBySha =
            Map<String, String?>.from(annotationPayloadJsonBySha),
        super(appDirProvider: () async => '/tmp/secondloop_test');

  final Map<String, String?> _annotationPayloadJsonBySha;
  int payloadReadCount = 0;

  @override
  Future<String?> readAttachmentAnnotationPayloadJson(
    Uint8List key, {
    required String sha256,
  }) async {
    payloadReadCount += 1;
    return _annotationPayloadJsonBySha[sha256];
  }
}
