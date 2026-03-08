import 'dart:convert';

class ExternalImportBatchDiagnostic {
  const ExternalImportBatchDiagnostic({
    required this.stage,
    required this.severity,
    required this.code,
    required this.message,
    required this.sourceRelPath,
    required this.createdAtMs,
  });

  final String stage;
  final String severity;
  final String code;
  final String message;
  final String? sourceRelPath;
  final int? createdAtMs;

  factory ExternalImportBatchDiagnostic.fromObject(Object? value) {
    final json = _asJsonMap(value);
    return ExternalImportBatchDiagnostic(
      stage: _toTrimmedString(json['stage']) ?? '',
      severity: _toTrimmedString(json['severity']) ?? '',
      code: _toTrimmedString(json['code']) ?? '',
      message: _toTrimmedString(json['message']) ?? '',
      sourceRelPath: _toTrimmedString(json['source_rel_path']),
      createdAtMs: _toNullableInt(json['created_at_ms']),
    );
  }

  Map<String, Object?> toJsonObject() {
    return <String, Object?>{
      'stage': stage,
      'severity': severity,
      'code': code,
      'message': message,
      'source_rel_path': sourceRelPath,
      'created_at_ms': createdAtMs,
    };
  }
}

class ExternalImportBatchReport {
  const ExternalImportBatchReport({
    required this.batchId,
    required this.sourceKind,
    required this.sourceLabel,
    required this.status,
    required this.notesCount,
    required this.attachmentsCount,
    required this.failedCount,
    required this.copiedBytes,
    required this.successCount,
    required this.copiedAttachmentCount,
    required this.diskUsageBytes,
    required this.elapsedMs,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.completedAtMs,
    required this.lastError,
    required this.diagnostics,
  });

  final String batchId;
  final String sourceKind;
  final String sourceLabel;
  final String status;
  final int notesCount;
  final int attachmentsCount;
  final int failedCount;
  final int copiedBytes;
  final int successCount;
  final int copiedAttachmentCount;
  final int diskUsageBytes;
  final int elapsedMs;
  final int createdAtMs;
  final int updatedAtMs;
  final int? completedAtMs;
  final String? lastError;
  final List<ExternalImportBatchDiagnostic> diagnostics;

  bool get hasDiagnostics => diagnostics.isNotEmpty;

  factory ExternalImportBatchReport.fromJsonString(String raw) {
    return ExternalImportBatchReport.fromObject(jsonDecode(raw));
  }

  factory ExternalImportBatchReport.fromObject(Object? value) {
    final json = _asJsonMap(value);
    final diagnosticsValue = json['diagnostics'];
    final diagnostics = diagnosticsValue is List
        ? diagnosticsValue
            .map(ExternalImportBatchDiagnostic.fromObject)
            .toList(growable: false)
        : const <ExternalImportBatchDiagnostic>[];
    return ExternalImportBatchReport(
      batchId: _toTrimmedString(json['batch_id']) ?? '',
      sourceKind: _toTrimmedString(json['source_kind']) ?? '',
      sourceLabel: _toTrimmedString(json['source_label']) ?? '',
      status: _toTrimmedString(json['status']) ?? '',
      notesCount: _toInt(json['notes_count']),
      attachmentsCount: _toInt(json['attachments_count']),
      failedCount: _toInt(json['failed_count']),
      copiedBytes: _toInt(json['copied_bytes']),
      successCount: _toInt(json['success_count']),
      copiedAttachmentCount: _toInt(json['copied_attachment_count']),
      diskUsageBytes: _toInt(json['disk_usage_bytes']),
      elapsedMs: _toInt(json['elapsed_ms']),
      createdAtMs: _toInt(json['created_at_ms']),
      updatedAtMs: _toInt(json['updated_at_ms']),
      completedAtMs: _toNullableInt(json['completed_at_ms']),
      lastError: _toTrimmedString(json['last_error']),
      diagnostics: diagnostics,
    );
  }

  Map<String, Object?> toJsonObject() {
    return <String, Object?>{
      'batch_id': batchId,
      'source_kind': sourceKind,
      'source_label': sourceLabel,
      'status': status,
      'notes_count': notesCount,
      'attachments_count': attachmentsCount,
      'failed_count': failedCount,
      'copied_bytes': copiedBytes,
      'success_count': successCount,
      'copied_attachment_count': copiedAttachmentCount,
      'disk_usage_bytes': diskUsageBytes,
      'elapsed_ms': elapsedMs,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'completed_at_ms': completedAtMs,
      'last_error': lastError,
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toJsonObject())
          .toList(growable: false),
    };
  }

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJsonObject());
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
