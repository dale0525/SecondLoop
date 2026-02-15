import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/attachment_annotation_job_status_row.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('AttachmentAnnotationJobStatusRow shows running after soft delay',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = AttachmentAnnotationJob(
      attachmentSha256: 'abc',
      status: 'pending',
      lang: 'en',
      modelName: null,
      attempts: 0,
      nextRetryAtMs: null,
      lastError: null,
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

    expect(find.text('AI analyzing…'), findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('AI analyzing…'), findsOneWidget);
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
}
