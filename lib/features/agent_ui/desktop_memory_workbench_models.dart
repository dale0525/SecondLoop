part of 'desktop_memory_workbench_page.dart';

List<_MemoryRecord> _recordsFromState(RuntimeAgentState state) {
  return state.memoryRecords
      .map(_MemoryRecord.fromRuntime)
      .toList(growable: false);
}

List<_MemoryCandidate> _candidatesFromState(RuntimeAgentState state) {
  return state.approvalItems
      .where(
        (item) => desktopRuntimeLooksLikeKind(
          item,
          const ['memory_confirmation', 'memory_candidate', 'memory'],
        ),
      )
      .map(_MemoryCandidate.fromApproval)
      .where((candidate) => candidate.id.isNotEmpty)
      .toList(growable: false);
}

final class _MemoryRecord {
  const _MemoryRecord({
    required this.id,
    required this.title,
    required this.detail,
    required this.status,
    required this.source,
    required this.sourceRef,
    required this.age,
    required this.contextId,
    required this.confidenceLabel,
  });

  final String id;
  final String title;
  final String detail;
  final String status;
  final String source;
  final String sourceRef;
  final String age;
  final String contextId;
  final String confidenceLabel;

  factory _MemoryRecord.fromRuntime(RuntimeWorkingSetRecord record) {
    final raw = record.raw;
    final title = desktopRuntimeString([
          record.title,
          raw['memory_text'],
          raw['instruction'],
          record.summary,
          record.body,
          record.text,
        ]) ??
        'Untitled memory';
    final detail = desktopRuntimeString([
          raw['instruction'],
          raw['memory_text'],
          record.body,
          record.summary,
          record.text,
          title,
        ]) ??
        title;
    final sourceRef = desktopRuntimeString([
          raw['source_message_id'],
          raw['sourceMessageId'],
          raw['source_entry_id'],
          raw['sourceEntryId'],
          raw['audit_id'],
          raw['auditId'],
        ]) ??
        'runtime';
    return _MemoryRecord(
      id: record.id.isNotEmpty ? record.id : sourceRef,
      title: title,
      detail: detail,
      status: desktopRuntimeString([record.status, raw['state']]) ?? 'active',
      source: desktopRuntimeString([
            raw['source'],
            raw['source_type'],
            raw['sourceType'],
            raw['tool'],
          ]) ??
          'Runtime',
      sourceRef: sourceRef,
      age: desktopRuntimeDateLabel(record.updatedAtMs),
      contextId: desktopRuntimeString([
            raw['context_snapshot_id'],
            raw['contextSnapshotId'],
            raw['context_id'],
            raw['contextId'],
          ]) ??
          '',
      confidenceLabel: _confidenceLabel(raw),
    );
  }
}

final class _MemoryCandidate {
  const _MemoryCandidate({
    required this.id,
    required this.title,
  });

  final String id;
  final String title;

  factory _MemoryCandidate.fromApproval(Map<String, Object?> item) {
    final record = desktopRuntimeMap(item['record']);
    return _MemoryCandidate(
      id: desktopRuntimeString([item['id'], item['approval_id']]) ?? '',
      title: desktopRuntimeString([
            record['memory_text'],
            record['instruction'],
            record['title'],
            item['title'],
            item['reason'],
          ]) ??
          'Memory candidate',
    );
  }
}

String _confidenceLabel(Map<String, Object?> raw) {
  final rawConfidence = raw['confidence_percent'] ??
      raw['confidencePercent'] ??
      raw['confidence'];
  if (rawConfidence is num) {
    final value = rawConfidence > 0 && rawConfidence <= 1
        ? (rawConfidence * 100).round()
        : rawConfidence.round();
    return '$value%';
  }
  final parsed = desktopRuntimeString([rawConfidence]);
  if (parsed == null) return 'not reported';
  return parsed.endsWith('%') ? parsed : parsed;
}
