import 'package:flutter/foundation.dart';

import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/secretary_runtime_client.dart';
import 'runtime_approval_record_helpers.dart';

@immutable
final class CalendarEventApprovalDetails {
  const CalendarEventApprovalDetails({
    required this.eventId,
    required this.title,
    required this.timeLabel,
    required this.attendeesLabel,
    required this.sourceMessage,
    required this.toolLabel,
    required this.auditId,
    required this.contextSnapshotId,
    required this.syncPriority,
    required this.notice,
    required this.statusLabel,
  });

  final String eventId;
  final String title;
  final String timeLabel;
  final String attendeesLabel;
  final String sourceMessage;
  final String toolLabel;
  final String auditId;
  final String contextSnapshotId;
  final String syncPriority;
  final String notice;
  final String statusLabel;

  factory CalendarEventApprovalDetails.fromRuntime({
    required SecretaryRuntimeApprovalItem item,
    RuntimeContextSnapshot? contextSnapshot,
    List<Map<String, Object?>> auditRefs = const <Map<String, Object?>>[],
  }) {
    final record = item.record ?? const <String, Object?>{};
    final eventId = runtimeApprovalFirstString([
          item.calendarEventId,
          record['calendar_event_id'],
          record['calendarEventId'],
          record['event_id'],
          record['eventId'],
          record['id'],
        ]) ??
        '';
    final title = runtimeApprovalFirstString([
          record['title'],
          record['summary'],
          item.title,
        ]) ??
        'Calendar event unavailable';
    final startsAtMs = runtimeApprovalFirstInt([
      record['starts_at_ms'],
      record['startsAtMs'],
      record['start_at_ms'],
      record['startAtMs'],
    ]);
    final endsAtMs = runtimeApprovalFirstInt([
      record['ends_at_ms'],
      record['endsAtMs'],
      record['end_at_ms'],
      record['endAtMs'],
    ]);
    final attendees = runtimeApprovalStringList(
      record['participants'] ??
          record['attendees'] ??
          record['invitees'] ??
          record['guests'],
    );
    final auditId = runtimeApprovalFirstString([
          record['audit_id'],
          record['auditId'],
          record['transaction_id'],
          record['transactionId'],
          _firstAuditId(auditRefs),
        ]) ??
        '';
    final contextSnapshotId = runtimeApprovalFirstString([
          record['context_snapshot_id'],
          record['contextSnapshotId'],
          contextSnapshot?.id,
        ]) ??
        '';
    return CalendarEventApprovalDetails(
      eventId: eventId.isEmpty ? 'unknown-calendar-event' : eventId,
      title: title,
      timeLabel: runtimeApprovalFirstString([
            record['time_label'],
            record['timeLabel'],
            record['schedule_label'],
            record['scheduleLabel'],
          ]) ??
          _calendarEventTimeLabel(startsAtMs, endsAtMs),
      attendeesLabel:
          attendees.isEmpty ? 'Attendees unavailable' : attendees.join(', '),
      sourceMessage: runtimeApprovalFirstString([
            record['source_message'],
            record['sourceMessage'],
            record['source'],
            item.reason,
          ]) ??
          'Source unavailable',
      toolLabel: runtimeApprovalFirstString([
            record['tool_label'],
            record['toolLabel'],
            record['runtime_tool'],
            record['runtimeTool'],
            record['tool'],
            record['skill'],
          ]) ??
          'calendar_tool',
      auditId: auditId.isEmpty ? 'Unavailable' : auditId,
      contextSnapshotId:
          contextSnapshotId.isEmpty ? 'Unavailable' : contextSnapshotId,
      syncPriority: runtimeApprovalFirstString([
            record['sync_priority'],
            record['syncPriority'],
            record['priority'],
          ]) ??
          'Standard',
      notice: runtimeApprovalFirstString([
            record['notice'],
            record['pending_notice'],
            record['pendingNotice'],
          ]) ??
          'Event will not be created until approved by user account owner.',
      statusLabel: runtimeApprovalFirstString([
            record['approval_status'],
            record['status'],
          ]) ??
          'pending',
    );
  }
}

String _calendarEventTimeLabel(int? startsAtMs, int? endsAtMs) {
  if (startsAtMs == null || startsAtMs <= 0) return 'Time unavailable';
  final start = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
  final end = endsAtMs == null || endsAtMs <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(endsAtMs);
  final date = '${_monthName(start.month)} ${start.day}, ${start.year}';
  final startTime = _clockLabel(start);
  final endTime = end == null ? null : _clockLabel(end);
  return endTime == null ? '$date, $startTime' : '$date, $startTime - $endTime';
}

String _clockLabel(DateTime value) {
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute $suffix';
}

String _monthName(int month) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  if (month < 1 || month > names.length) return 'Month';
  return names[month - 1];
}

String? _firstAuditId(List<Map<String, Object?>> refs) {
  for (final ref in refs) {
    final value = runtimeApprovalFirstString([
      ref['id'],
      ref['audit_id'],
      ref['auditId'],
      ref['transaction_id'],
      ref['transactionId'],
    ]);
    if (value != null) return value;
  }
  return null;
}
