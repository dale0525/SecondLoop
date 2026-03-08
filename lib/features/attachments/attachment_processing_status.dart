import '../../i18n/strings.g.dart';

enum AttachmentProcessingStage {
  none,
  preparing,
  preparingVideo,
  transcodingVideo,
  generatingKeyframes,
  extractingAudio,
  transcodingAudio,
  finalizingAttachment,
  waitingForSpeechRecognition,
  transcribingAudio,
  understandingKeyframes,
  recognizingText,
  analyzingImage,
  analyzingAttachment,
  failed,
  canceled,
}

typedef AttachmentProcessingPayload = Map<String, Object?>;
typedef AttachmentProcessingStageCallback = void Function(
  AttachmentProcessingStage stage,
);

String attachmentProcessingAutoOcrStatusFromPayload(
  AttachmentProcessingPayload? payload,
) {
  return (payload?['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
}

bool attachmentProcessingOcrInProgressFromPayload(
  AttachmentProcessingPayload? payload,
) {
  if (payload == null) return false;

  final status = attachmentProcessingAutoOcrStatusFromPayload(payload);
  if (status == 'running' || status == 'queued' || status == 'retrying') {
    return true;
  }
  if (payload['ocr_running'] == true) return true;
  if (status == 'ok' || status == 'failed') return false;
  if (payload['needs_ocr'] != true) return false;

  return !_hasAnyReadableText(
    payload,
    const <String>['ocr_text_excerpt', 'ocr_text_full', 'ocr_text'],
  );
}

AttachmentProcessingStage resolveAttachmentProcessingStage({
  required String mimeType,
  String? jobStatus,
  AttachmentProcessingPayload? payload,
}) {
  final normalizedMimeType = mimeType.trim().toLowerCase();
  final normalizedJobStatus = (jobStatus ?? '').trim().toLowerCase();

  if (normalizedJobStatus == 'failed') {
    return AttachmentProcessingStage.failed;
  }
  if (normalizedJobStatus == 'canceled') {
    return AttachmentProcessingStage.canceled;
  }

  final schema = _payloadString(payload, 'schema').toLowerCase();
  final autoOcrStatus = attachmentProcessingAutoOcrStatusFromPayload(payload);
  final hasTranscript = _hasAnyReadableText(
    payload,
    const <String>['transcript_excerpt', 'transcript_full'],
  );
  final hasDerivedVideoUnderstanding = _hasAnyReadableText(
    payload,
    const <String>[
      'video_summary',
      'knowledge_markdown_excerpt',
      'knowledge_markdown_full',
      'video_description_excerpt',
      'video_description_full',
      'ocr_text_excerpt',
      'ocr_text_full',
      'ocr_text',
    ],
  );
  final hasLinkedAudio = _payloadString(payload, 'audio_sha256').isNotEmpty ||
      _payloadString(payload, 'audio_mime_type').startsWith('audio/');
  final needsOcr = payload?['needs_ocr'] == true;
  final hasOcrText = _hasAnyReadableText(
    payload,
    const <String>['ocr_text_excerpt', 'ocr_text_full', 'ocr_text'],
  );

  final isVideoManifest =
      normalizedMimeType == 'application/x.secondloop.video+json' ||
          schema == 'secondloop.video_extract.v1' ||
          schema.startsWith('secondloop.video_manifest.');
  final isAudio = normalizedMimeType.startsWith('audio/');
  final isImage = normalizedMimeType.startsWith('image/');
  final isDocument = _isDocumentMimeType(normalizedMimeType);

  if (isVideoManifest) {
    if (autoOcrStatus == 'queued' || autoOcrStatus == 'retrying') {
      if (!hasTranscript && hasLinkedAudio) {
        return AttachmentProcessingStage.waitingForSpeechRecognition;
      }
      return AttachmentProcessingStage.understandingKeyframes;
    }
    if (autoOcrStatus == 'running') {
      if (!hasTranscript && hasLinkedAudio) {
        return AttachmentProcessingStage.transcribingAudio;
      }
      return AttachmentProcessingStage.understandingKeyframes;
    }
    if (needsOcr && !hasDerivedVideoUnderstanding) {
      if (!hasTranscript && hasLinkedAudio) {
        return AttachmentProcessingStage.waitingForSpeechRecognition;
      }
      return AttachmentProcessingStage.understandingKeyframes;
    }
    if (normalizedJobStatus == 'pending' || normalizedJobStatus == 'running') {
      return AttachmentProcessingStage.preparingVideo;
    }
    return AttachmentProcessingStage.none;
  }

  if (isAudio &&
      (normalizedJobStatus == 'pending' || normalizedJobStatus == 'running')) {
    return AttachmentProcessingStage.transcribingAudio;
  }

  if (isDocument &&
      (normalizedJobStatus == 'pending' || normalizedJobStatus == 'running') &&
      !hasOcrText) {
    return AttachmentProcessingStage.recognizingText;
  }

  if ((isDocument ||
          needsOcr ||
          attachmentProcessingOcrInProgressFromPayload(payload)) &&
      (autoOcrStatus == 'queued' ||
          autoOcrStatus == 'running' ||
          autoOcrStatus == 'retrying' ||
          (needsOcr && !hasOcrText))) {
    return AttachmentProcessingStage.recognizingText;
  }

  if (isImage &&
      (normalizedJobStatus == 'pending' || normalizedJobStatus == 'running')) {
    return AttachmentProcessingStage.analyzingImage;
  }

  if (normalizedJobStatus == 'pending' || normalizedJobStatus == 'running') {
    return AttachmentProcessingStage.analyzingAttachment;
  }

  return AttachmentProcessingStage.none;
}

bool attachmentProcessingStageIsActive(AttachmentProcessingStage stage) {
  switch (stage) {
    case AttachmentProcessingStage.none:
    case AttachmentProcessingStage.failed:
    case AttachmentProcessingStage.canceled:
      return false;
    default:
      return true;
  }
}

String attachmentProcessingStageLabel(
  Translations t,
  AttachmentProcessingStage stage,
) {
  switch (stage) {
    case AttachmentProcessingStage.none:
      return '';
    case AttachmentProcessingStage.preparing:
      return t.sync.progressDialog.preparing;
    case AttachmentProcessingStage.preparingVideo:
      return t.attachments.processing.preparingVideo;
    case AttachmentProcessingStage.transcodingVideo:
      return t.attachments.processing.transcodingVideo;
    case AttachmentProcessingStage.generatingKeyframes:
      return t.attachments.processing.generatingKeyframes;
    case AttachmentProcessingStage.extractingAudio:
      return t.attachments.processing.extractingAudio;
    case AttachmentProcessingStage.transcodingAudio:
      return t.attachments.processing.transcodingAudio;
    case AttachmentProcessingStage.finalizingAttachment:
      return t.attachments.processing.finalizingAttachment;
    case AttachmentProcessingStage.waitingForSpeechRecognition:
      return t.attachments.processing.waitingForSpeechRecognition;
    case AttachmentProcessingStage.transcribingAudio:
      return t.attachments.processing.transcribingAudio;
    case AttachmentProcessingStage.understandingKeyframes:
      return t.attachments.processing.understandingKeyframes;
    case AttachmentProcessingStage.recognizingText:
      return t.attachments.processing.recognizingText;
    case AttachmentProcessingStage.analyzingImage:
      return t.attachments.processing.analyzingImage;
    case AttachmentProcessingStage.analyzingAttachment:
      return t.attachments.processing.analyzingAttachment;
    case AttachmentProcessingStage.failed:
    case AttachmentProcessingStage.canceled:
      return '';
  }
}

bool _isDocumentMimeType(String mimeType) {
  if (mimeType == 'application/pdf') return true;
  if (mimeType.startsWith('text/')) return true;
  if (mimeType.contains('officedocument')) return true;
  if (mimeType.contains('msword')) return true;
  if (mimeType.contains('ms-excel')) return true;
  if (mimeType.contains('ms-powerpoint')) return true;
  return false;
}

String _payloadString(AttachmentProcessingPayload? payload, String key) {
  return (payload?[key] ?? '').toString().trim();
}

bool _hasAnyReadableText(
  AttachmentProcessingPayload? payload,
  List<String> keys,
) {
  if (payload == null) return false;
  for (final key in keys) {
    final value = _payloadString(payload, key);
    if (value.isNotEmpty && value.toLowerCase() != 'null') {
      return true;
    }
  }
  return false;
}
