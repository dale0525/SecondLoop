import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/attachment_annotation_job_ui_state.dart';
import 'package:secondloop/i18n/strings.g.dart';

void main() {
  test('audio jobs use audio transcribe state and setup label', () {
    final uiState = resolveAttachmentAnnotationJobUiState(
      mimeType: 'audio/mp4',
      t: AppLocale.en.build(),
      isZhLocale: false,
      annotationEnabled: false,
      annotationCanRunNow: false,
      audioTranscribeEnabled: true,
      audioTranscribeCanRunNow: true,
    );

    expect(uiState.enabled, isTrue);
    expect(uiState.canRunNow, isTrue);
    expect(uiState.setupRequiredLabel, 'Audio transcription needs setup');
  });

  test('image jobs keep image annotation state and setup label', () {
    final uiState = resolveAttachmentAnnotationJobUiState(
      mimeType: 'image/png',
      t: AppLocale.en.build(),
      isZhLocale: false,
      annotationEnabled: false,
      annotationCanRunNow: false,
      audioTranscribeEnabled: true,
      audioTranscribeCanRunNow: true,
    );

    expect(uiState.enabled, isFalse);
    expect(uiState.canRunNow, isFalse);
    expect(uiState.setupRequiredLabel, 'Image annotations need setup');
  });

  test('audio jobs use zh setup label in Chinese locale', () {
    final uiState = resolveAttachmentAnnotationJobUiState(
      mimeType: 'video/mp4',
      t: AppLocale.zhCn.build(),
      isZhLocale: true,
      annotationEnabled: false,
      annotationCanRunNow: false,
      audioTranscribeEnabled: false,
      audioTranscribeCanRunNow: false,
    );

    expect(uiState.setupRequiredLabel, '音频转写需要先配置');
  });
}
