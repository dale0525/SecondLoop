import 'attachment_text_source_policy.dart';

bool shouldRefreshAttachmentAnnotationPayloadOnSync({
  required Map<String, Object?>? payload,
  required bool ocrRunning,
  required String? ocrStatusText,
}) {
  if (payload == null) return true;
  if (ocrRunning) return true;

  final status = (ocrStatusText ?? '').trim();
  if (status.isNotEmpty) return true;

  final autoStatus =
      (payload['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
  if (autoStatus == 'running' ||
      autoStatus == 'queued' ||
      autoStatus == 'retrying') {
    return true;
  }

  final selected = selectAttachmentDisplayText(payload);
  if (!selected.hasAnyText) return true;

  return false;
}
