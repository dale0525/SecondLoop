import 'dart:convert';

class ExternalImportPhaseBEstimate {
  const ExternalImportPhaseBEstimate({
    required this.batchId,
    required this.eligibleAttachmentCount,
    required this.remainingAttachmentCount,
    required this.estimatedRuntimeSeconds,
    required this.estimatedCloudTokens,
    required this.estimatedLocalBytes,
    required this.estimatedLocalWorkUnits,
    required this.phaseBStatus,
  });

  final String batchId;
  final int eligibleAttachmentCount;
  final int remainingAttachmentCount;
  final int estimatedRuntimeSeconds;
  final int estimatedCloudTokens;
  final int estimatedLocalBytes;
  final int estimatedLocalWorkUnits;
  final String phaseBStatus;

  factory ExternalImportPhaseBEstimate.fromJsonString(String raw) {
    return ExternalImportPhaseBEstimate.fromObject(jsonDecode(raw));
  }

  factory ExternalImportPhaseBEstimate.fromObject(Object? value) {
    final json = _asJsonMap(value);
    return ExternalImportPhaseBEstimate(
      batchId: _toTrimmedString(json['batch_id']) ?? '',
      eligibleAttachmentCount: _toInt(json['eligible_attachment_count']),
      remainingAttachmentCount: _toInt(json['remaining_attachment_count']),
      estimatedRuntimeSeconds: _toInt(json['estimated_runtime_seconds']),
      estimatedCloudTokens: _toInt(json['estimated_cloud_tokens']),
      estimatedLocalBytes: _toInt(json['estimated_local_bytes']),
      estimatedLocalWorkUnits: _toInt(json['estimated_local_work_units']),
      phaseBStatus: _toTrimmedString(json['phase_b_status']) ?? 'not_started',
    );
  }
}

class ExternalImportPhaseBState {
  const ExternalImportPhaseBState({
    required this.batchId,
    required this.batchStatus,
    required this.phaseBStatus,
    required this.notesCount,
    required this.attachmentsCount,
    required this.failedCount,
    required this.copiedBytes,
    required this.eligibleAttachmentCount,
    required this.processedAttachmentCount,
    required this.remainingAttachmentCount,
    required this.failedAttachmentCount,
    required this.enrichedChunkCount,
    required this.successDocCount,
    required this.attachmentRefCount,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.completedAtMs,
    required this.elapsedMs,
    required this.phaseBStartedAtMs,
    required this.phaseBCompletedAtMs,
    required this.phaseBElapsedMs,
    required this.lastError,
    required this.phaseBLastError,
  });

  final String batchId;
  final String batchStatus;
  final String phaseBStatus;
  final int notesCount;
  final int attachmentsCount;
  final int failedCount;
  final int copiedBytes;
  final int eligibleAttachmentCount;
  final int processedAttachmentCount;
  final int remainingAttachmentCount;
  final int failedAttachmentCount;
  final int enrichedChunkCount;
  final int successDocCount;
  final int attachmentRefCount;
  final int createdAtMs;
  final int updatedAtMs;
  final int? completedAtMs;
  final int elapsedMs;
  final int? phaseBStartedAtMs;
  final int? phaseBCompletedAtMs;
  final int phaseBElapsedMs;
  final String? lastError;
  final String? phaseBLastError;

  bool get isInProgress => phaseBStatus == 'in_progress';
  bool get isNotStarted => phaseBStatus == 'not_started';
  bool get isCompleted => phaseBStatus == 'completed';
  bool get isNoWork => phaseBStatus == 'no_work';
  bool get canStart => batchStatus == 'completed' && !isCompleted && !isNoWork;

  factory ExternalImportPhaseBState.fromJsonString(String raw) {
    return ExternalImportPhaseBState.fromObject(jsonDecode(raw));
  }

  factory ExternalImportPhaseBState.fromObject(Object? value) {
    final json = _asJsonMap(value);
    return ExternalImportPhaseBState(
      batchId: _toTrimmedString(json['batch_id']) ?? '',
      batchStatus: _toTrimmedString(json['batch_status']) ?? '',
      phaseBStatus: _toTrimmedString(json['phase_b_status']) ?? 'not_started',
      notesCount: _toInt(json['notes_count']),
      attachmentsCount: _toInt(json['attachments_count']),
      failedCount: _toInt(json['failed_count']),
      copiedBytes: _toInt(json['copied_bytes']),
      eligibleAttachmentCount: _toInt(json['eligible_attachment_count']),
      processedAttachmentCount: _toInt(json['processed_attachment_count']),
      remainingAttachmentCount: _toInt(json['remaining_attachment_count']),
      failedAttachmentCount: _toInt(json['failed_attachment_count']),
      enrichedChunkCount: _toInt(json['enriched_chunk_count']),
      successDocCount: _toInt(json['success_doc_count']),
      attachmentRefCount: _toInt(json['attachment_ref_count']),
      createdAtMs: _toInt(json['created_at_ms']),
      updatedAtMs: _toInt(json['updated_at_ms']),
      completedAtMs: _toNullableInt(json['completed_at_ms']),
      elapsedMs: _toInt(json['elapsed_ms']),
      phaseBStartedAtMs: _toNullableInt(json['phase_b_started_at_ms']),
      phaseBCompletedAtMs: _toNullableInt(json['phase_b_completed_at_ms']),
      phaseBElapsedMs: _toInt(json['phase_b_elapsed_ms']),
      lastError: _toTrimmedString(json['last_error']),
      phaseBLastError: _toTrimmedString(json['phase_b_last_error']),
    );
  }

  static ExternalImportPhaseBState? tryFromObject(Object? value) {
    if (value == null) return null;
    final json = _asJsonMap(value);
    final batchId = _toTrimmedString(json['batch_id']);
    if (batchId == null || batchId.isEmpty) {
      return null;
    }
    return ExternalImportPhaseBState.fromObject(json);
  }
}

Map<String, Object?> _asJsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(
      value.map((key, entryValue) => MapEntry(key.toString(), entryValue)),
    );
  }
  return const <String, Object?>{};
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _toNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

String? _toTrimmedString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}
