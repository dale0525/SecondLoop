import 'package:flutter/material.dart';

import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/secretary_runtime_client.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_operating_system_tokens.dart';
import 'calendar_event_approval_details.dart';

final class CalendarEventApprovalCard extends StatelessWidget {
  const CalendarEventApprovalCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
    this.contextSnapshot,
    this.auditRefs = const <Map<String, Object?>>[],
    this.onEdit,
    this.busy = false,
    super.key,
  });

  final SecretaryRuntimeApprovalItem item;
  final RuntimeContextSnapshot? contextSnapshot;
  final List<Map<String, Object?>> auditRefs;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final details = CalendarEventApprovalDetails.fromRuntime(
      item: item,
      contextSnapshot: contextSnapshot,
      auditRefs: auditRefs,
    );
    return KeyedSubtree(
      key: ValueKey('approval_preview_card_${item.id}'),
      child: DecoratedBox(
        key: ValueKey('calendar_event_approval_card_${item.id}'),
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surface,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
          border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CalendarApprovalHeader(details: details),
            Padding(
              padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CalendarEventSummary(details: details),
                  const SizedBox(height: AgentDesignTokens.gapMd),
                  _CalendarPendingNotice(notice: details.notice),
                  const SizedBox(height: AgentDesignTokens.gapLg),
                  _CalendarMetadataGrid(details: details),
                  const SizedBox(height: AgentDesignTokens.gapLg),
                  _CalendarApprovalActions(
                    item: item,
                    busy: busy,
                    editAvailable: onEdit != null,
                    onApprove: onApprove,
                    onEdit: onEdit,
                    onReject: onReject,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CalendarApprovalHeader extends StatelessWidget {
  const _CalendarApprovalHeader({required this.details});

  final CalendarEventApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AgentOperatingSystemTokens.radiusLg),
        ),
        border: Border(
          bottom: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              color: AgentOperatingSystemTokens.onSurface,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Calendar Event Approval',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.headlineSm.copyWith(
                  color: AgentOperatingSystemTokens.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ToolChip(label: details.toolLabel),
          ],
        ),
      ),
    );
  }
}

final class _CalendarEventSummary extends StatelessWidget {
  const _CalendarEventSummary({required this.details});

  final CalendarEventApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Proposed Event'.toUpperCase(),
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.outline,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          details.title,
          key: ValueKey('calendar_event_title_${details.eventId}'),
          style: AgentOperatingSystemTokens.headlineSm.copyWith(
            color: AgentOperatingSystemTokens.onSurface,
          ),
        ),
        const SizedBox(height: AgentDesignTokens.gapMd),
        _CalendarEventFactRow(
          icon: Icons.schedule_rounded,
          keyName: 'calendar_event_time_${details.eventId}',
          text: details.timeLabel,
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        _CalendarEventFactRow(
          icon: Icons.group_outlined,
          keyName: 'calendar_event_attendees_${details.eventId}',
          text: details.attendeesLabel,
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        _CalendarEventFactRow(
          icon: Icons.mail_outline_rounded,
          keyName: 'calendar_event_source_${details.eventId}',
          text: details.sourceMessage,
        ),
      ],
    );
  }
}

final class _CalendarEventFactRow extends StatelessWidget {
  const _CalendarEventFactRow({
    required this.icon,
    required this.keyName,
    required this.text,
  });

  final IconData icon;
  final String keyName;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: AgentOperatingSystemTokens.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            key: ValueKey(keyName),
            style: AgentOperatingSystemTokens.bodyMd.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

final class _CalendarPendingNotice extends StatelessWidget {
  const _CalendarPendingNotice({required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notice,
                style: AgentOperatingSystemTokens.labelLg.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CalendarMetadataGrid extends StatelessWidget {
  const _CalendarMetadataGrid({required this.details});

  final CalendarEventApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Audit Trail', details.auditId),
      ('Sync Priority', details.syncPriority),
      ('Context Snapshot', details.contextSnapshotId),
      ('Status', details.statusLabel),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth >= 520
                ? (constraints.maxWidth - AgentDesignTokens.gapMd * 3) / 4
                : (constraints.maxWidth - AgentDesignTokens.gapMd) / 2;
            return Wrap(
              spacing: AgentDesignTokens.gapMd,
              runSpacing: AgentDesignTokens.gapMd,
              children: [
                for (final item in items)
                  SizedBox(
                    width:
                        tileWidth.clamp(120.0, constraints.maxWidth).toDouble(),
                    child: _CalendarMetadataTile(
                      label: item.$1,
                      value: item.$2,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final class _CalendarMetadataTile extends StatelessWidget {
  const _CalendarMetadataTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.outline,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AgentOperatingSystemTokens.labelLg.copyWith(
            color: AgentOperatingSystemTokens.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

final class _CalendarApprovalActions extends StatelessWidget {
  const _CalendarApprovalActions({
    required this.item,
    required this.busy,
    required this.editAvailable,
    required this.onApprove,
    required this.onEdit,
    required this.onReject,
  });

  final SecretaryRuntimeApprovalItem item;
  final bool busy;
  final bool editAvailable;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(
          height: 1,
          color: AgentOperatingSystemTokens.outlineVariant,
        ),
        const SizedBox(height: AgentDesignTokens.gapLg),
        FilledButton.icon(
          key: ValueKey('calendar_event_approve_${item.id}'),
          onPressed: busy ? null : onApprove,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(busy ? 'Processing...' : 'Approve Event'),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        OutlinedButton.icon(
          key: ValueKey('calendar_event_edit_${item.id}'),
          onPressed: busy || !editAvailable ? null : onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(editAvailable ? 'Edit' : 'Edit unavailable'),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        OutlinedButton.icon(
          key: ValueKey('calendar_event_reject_${item.id}'),
          onPressed: busy ? null : onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            side: BorderSide(color: Colors.red.shade200),
          ),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Reject'),
        ),
      ],
    );
  }
}

final class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.terminal_rounded,
              size: 14,
              color: AgentOperatingSystemTokens.outline,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AgentOperatingSystemTokens.code.copyWith(
                color: AgentOperatingSystemTokens.outline,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
