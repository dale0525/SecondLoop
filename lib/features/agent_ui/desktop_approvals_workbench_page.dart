import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/runtime_agent_state_repository.dart';
import '../../core/cloud/runtime_connection_helpers.dart';
import '../../core/cloud/secretary_runtime_conversation_sender.dart';
import 'agent_desktop_runtime_helpers.dart';
import 'agent_desktop_workbench_widgets.dart';
import 'agent_operating_system_tokens.dart';

part 'desktop_approvals_workbench_models.dart';

final class DesktopApprovalsWorkbenchPage extends StatefulWidget {
  const DesktopApprovalsWorkbenchPage({
    this.runtimeAgentStateRepository,
    this.approvalSender,
    this.vaultId,
    this.conversationId = 'loop_home',
    super.key,
  });

  final RuntimeAgentStateRepository? runtimeAgentStateRepository;
  final ChatRuntimeApprovalSender? approvalSender;
  final String? vaultId;
  final String conversationId;

  @override
  State<DesktopApprovalsWorkbenchPage> createState() =>
      _DesktopApprovalsWorkbenchPageState();
}

final class _DesktopApprovalsWorkbenchPageState
    extends State<DesktopApprovalsWorkbenchPage> {
  RuntimeAgentState? _state;
  String? _selectedApprovalId;
  String _filter = 'pending';
  String? _error;
  bool _loading = false;
  bool _didLoad = false;
  String? _busyApprovalId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant DesktopApprovalsWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtimeAgentStateRepository !=
            widget.runtimeAgentStateRepository ||
        oldWidget.vaultId != widget.vaultId ||
        oldWidget.conversationId != widget.conversationId) {
      unawaited(_refresh());
    }
  }

  RuntimeAgentStateRepository? _repository() {
    if (widget.runtimeAgentStateRepository != null) {
      return widget.runtimeAgentStateRepository;
    }
    if (cachedSelfManagedRuntimeConnection() != null) {
      return SecretaryRuntimeAgentStateRepository();
    }
    final scope = CloudAuthScope.maybeOf(context);
    final vaultId = scope?.controller.uid?.trim() ?? '';
    if (scope == null || vaultId.isEmpty) return null;
    return SecretaryRuntimeAgentStateRepository.hostedManagedPro(
      apiBaseUrl: scope.gatewayConfig.baseUrl,
      hostedSessionTokenGetter: scope.controller.getIdToken,
    );
  }

  ChatRuntimeApprovalSender? _approvalSender() {
    if (widget.approvalSender != null) return widget.approvalSender;
    if (cachedSelfManagedRuntimeConnection() != null) {
      return SecretaryRuntimeConversationSender();
    }
    final scope = CloudAuthScope.maybeOf(context);
    final vaultId = scope?.controller.uid?.trim() ?? '';
    if (scope == null || vaultId.isEmpty) return null;
    return SecretaryRuntimeConversationSender.hostedManagedPro(
      apiBaseUrl: scope.gatewayConfig.baseUrl,
      hostedSessionTokenGetter: scope.controller.getIdToken,
    );
  }

  String _vaultId() {
    final explicit = widget.vaultId?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final selfManagedVaultId =
        cachedSelfManagedRuntimeConnection()?.profile.vaultId.trim() ?? '';
    if (selfManagedVaultId.isNotEmpty) return selfManagedVaultId;
    return CloudAuthScope.maybeOf(context)?.controller.uid?.trim() ?? '';
  }

  Future<void> _refresh() async {
    if (widget.runtimeAgentStateRepository == null &&
        (widget.vaultId?.trim().isEmpty ?? true)) {
      await loadRuntimeConnectionSafely();
      if (!mounted) return;
    }
    final repository = _repository();
    final vaultId = _vaultId();
    if (repository == null || vaultId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'tool_unavailable: runtime state is not configured';
        _state = RuntimeAgentState.empty(
          vaultId: vaultId,
          conversationId: widget.conversationId,
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await repository.fetchAgentState(
        vaultId: vaultId,
        conversationId: widget.conversationId,
      );
      if (!mounted) return;
      final approvals = _approvalsFromState(state);
      setState(() {
        _state = state;
        _loading = false;
        _selectedApprovalId =
            approvals.any((item) => item.id == _selectedApprovalId)
                ? _selectedApprovalId
                : approvals.firstOrNull?.id;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'tool_unavailable: $error';
        _state ??= RuntimeAgentState.empty(
          vaultId: vaultId,
          conversationId: widget.conversationId,
        );
      });
    }
  }

  Future<void> _submitDecision(
    _ApprovalView approval,
    String decision,
  ) async {
    if (!approval.canSubmitDecision(decision)) {
      showDesktopWorkbenchMessage(
        context,
        '${approval.status}: this approval cannot be ${decision}d from the app.',
      );
      return;
    }
    final sender = _approvalSender();
    final vaultId = _vaultId();
    if (sender == null || vaultId.isEmpty) {
      showDesktopWorkbenchMessage(
        context,
        'tool_unavailable: runtime approval sender is not configured',
      );
      return;
    }
    setState(() => _busyApprovalId = approval.id);
    try {
      await sender.submitApprovalDecision(
        vaultId: vaultId,
        approvalId: approval.id,
        decision: decision,
      );
      if (!mounted) return;
      showDesktopWorkbenchMessage(context, 'approval decision submitted');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showDesktopWorkbenchMessage(context, 'tool_unavailable: $error');
    } finally {
      if (mounted) setState(() => _busyApprovalId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final approvals =
        state == null ? const <_ApprovalView>[] : _approvalsFromState(state);
    final filtered = _filterApprovals(approvals);
    final selected = _selectedApprovalId == null
        ? filtered.firstOrNull
        : filtered
                .where((approval) => approval.id == _selectedApprovalId)
                .firstOrNull ??
            filtered.firstOrNull;

    return DesktopWorkbenchPageShell(
      key: const ValueKey('desktop_approvals_workbench_page'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopWorkbenchHeader(
            title: 'Approvals',
            subtitle:
                'Review guarded mutations before they affect your vault or external systems',
            actions: [
              IconButton.outlined(
                key: const ValueKey('desktop_approvals_refresh'),
                tooltip: 'Refresh approvals',
                onPressed: _loading ? null : () => unawaited(_refresh()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            bottom: _ApprovalFilterBar(
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
          ),
          const SizedBox(height: 24),
          if (_loading && state == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 4,
                    child: _ApprovalQueue(
                      approvals: filtered,
                      selectedId: selected?.id,
                      onSelect: (approval) => setState(
                        () => _selectedApprovalId = approval.id,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 5,
                    child: _ApprovalDetail(
                      approval: selected,
                      busy: selected != null &&
                          _busyApprovalId != null &&
                          _busyApprovalId == selected.id,
                      onRequestChanges: () => showDesktopWorkbenchMessage(
                        context,
                        'tool_unavailable: approval edit requests are not available yet',
                      ),
                      onReject: selected == null
                          ? null
                          : () => unawaited(
                                _submitDecision(selected, 'reject'),
                              ),
                      onApprove: selected == null
                          ? null
                          : () => unawaited(
                                _submitDecision(selected, 'approve'),
                              ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: _ApprovalAuditPanel(
                      approval: selected,
                      state: state,
                      error: _error,
                      loading: _loading,
                      onConfigure: () => showDesktopWorkbenchMessage(
                        context,
                        'needs_configuration: connector configuration is not available from this panel yet',
                      ),
                      onRetry: _loading ? null : () => unawaited(_refresh()),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_ApprovalView> _filterApprovals(List<_ApprovalView> approvals) {
    if (_filter == 'pending') {
      return approvals
          .where((item) =>
              item.status.contains('pending') ||
              item.needsConfig ||
              item.refused)
          .toList(growable: false);
    }
    if (_filter == 'needs_config') {
      return approvals
          .where((item) => item.needsConfig)
          .toList(growable: false);
    }
    if (_filter == 'high_risk') {
      return approvals.where((item) => item.risk == 'High Risk').toList(
            growable: false,
          );
    }
    if (_filter == 'rejected') {
      return approvals
          .where((item) => item.status.contains('reject') || item.refused)
          .toList(growable: false);
    }
    return approvals
        .where((item) => item.status.contains(_filter))
        .toList(growable: false);
  }
}

final class _ApprovalFilterBar extends StatelessWidget {
  const _ApprovalFilterBar({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = {
      'pending': 'Pending',
      'approved': 'Approved',
      'rejected': 'Rejected',
      'needs_config': 'Needs config',
      'high_risk': 'High risk',
    };
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in filters.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: selected == entry.key,
            onSelected: (_) => onSelected(entry.key),
          ),
      ],
    );
  }
}

final class _ApprovalQueue extends StatelessWidget {
  const _ApprovalQueue({
    required this.approvals,
    required this.selectedId,
    required this.onSelect,
  });

  final List<_ApprovalView> approvals;
  final String? selectedId;
  final ValueChanged<_ApprovalView> onSelect;

  @override
  Widget build(BuildContext context) {
    if (approvals.isEmpty) {
      return const DesktopWorkbenchEmptyState(
        title: 'No matching approvals',
        message:
            'Guarded runtime mutations will appear here when approval is required.',
        icon: Icons.verified_user_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(right: 4),
      itemCount: approvals.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final approval = approvals[index];
        return _ApprovalQueueCard(
          key: ValueKey('desktop_approval_queue_${approval.id}'),
          approval: approval,
          selected: approval.id == selectedId,
          onTap: () => onSelect(approval),
        );
      },
    );
  }
}

final class _ApprovalQueueCard extends StatelessWidget {
  const _ApprovalQueueCard({
    required this.approval,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _ApprovalView approval;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AgentOperatingSystemTokens.secondary
                : AgentOperatingSystemTokens.outlineVariant,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      approval.typeLabel,
                      style: AgentOperatingSystemTokens.labelMd.copyWith(
                        color: selected
                            ? AgentOperatingSystemTokens.secondary
                            : AgentOperatingSystemTokens.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  DesktopWorkbenchBadge(
                    label: approval.risk,
                    background: approval.risk == 'High Risk'
                        ? const Color(0xFFFFDAD6)
                        : AgentOperatingSystemTokens.surfaceContainerHigh,
                    foreground: approval.risk == 'High Risk'
                        ? const Color(0xFF93000A)
                        : AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                approval.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  color: approval.refused
                      ? AgentOperatingSystemTokens.onSurfaceVariant
                      : AgentOperatingSystemTokens.onSurface,
                  decoration:
                      approval.refused ? TextDecoration.lineThrough : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    approval.refused
                        ? Icons.block_rounded
                        : approval.needsConfig
                            ? Icons.settings_outlined
                            : Icons.pending_actions_rounded,
                    size: 14,
                    color: desktopStatusColor(approval.status),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      approval.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgentOperatingSystemTokens.labelMd.copyWith(
                        color: desktopStatusColor(approval.status),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ApprovalDetail extends StatelessWidget {
  const _ApprovalDetail({
    required this.approval,
    required this.busy,
    required this.onRequestChanges,
    required this.onReject,
    required this.onApprove,
  });

  final _ApprovalView? approval;
  final bool busy;
  final VoidCallback onRequestChanges;
  final VoidCallback? onReject;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final approval = this.approval;
    if (approval == null) {
      return const DesktopWorkbenchPanel(
        title: 'Proposed Change',
        child: DesktopWorkbenchEmptyState(
          title: 'Select an approval',
          message:
              'Choose an item to inspect the mutation diff and audit trail.',
          icon: Icons.fact_check_outlined,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: AgentOperatingSystemTokens.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                runSpacing: 6,
                spacing: 16,
                children: [
                  _CodePair(label: 'approval_id', value: approval.id),
                  _CodePair(label: 'type', value: approval.kind),
                  _CodePair(label: 'target', value: approval.targetId),
                  _CodePair(label: 'source', value: approval.sourceId),
                  DesktopWorkbenchBadge(label: 'Risk: ${approval.risk}'),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Proposed Change',
                    style: AgentOperatingSystemTokens.headlineSm.copyWith(
                      color: AgentOperatingSystemTokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AgentOperatingSystemTokens.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ColoredBox(
                          color: AgentOperatingSystemTokens.surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Text(
                              approval.targetLabel,
                              style:
                                  AgentOperatingSystemTokens.labelMd.copyWith(
                                color:
                                    AgentOperatingSystemTokens.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              _DiffLine(
                                icon: Icons.remove_rounded,
                                color: const Color(0xFFBA1A1A),
                                background: const Color(0x22FFDAD6),
                                text: approval.before,
                              ),
                              const SizedBox(height: 8),
                              _DiffLine(
                                icon: Icons.add_rounded,
                                color: AgentOperatingSystemTokens.secondary,
                                background: const Color(0x1A0051D5),
                                text: approval.after,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: AgentOperatingSystemTokens.secondary,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        approval.reason,
                        style: AgentOperatingSystemTokens.bodySm.copyWith(
                          color: AgentOperatingSystemTokens.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(
            height: 1,
            color: AgentOperatingSystemTokens.outlineVariant,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const ValueKey('desktop_approval_request_changes'),
                  onPressed: onRequestChanges,
                  child: const Text('Request changes'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const ValueKey('desktop_approval_reject'),
                  onPressed: busy || !approval.canSubmitDecision('reject')
                      ? null
                      : onReject,
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const ValueKey('desktop_approval_approve'),
                  onPressed: busy || !approval.canSubmitDecision('approve')
                      ? null
                      : onApprove,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Approve'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ApprovalAuditPanel extends StatelessWidget {
  const _ApprovalAuditPanel({
    required this.approval,
    required this.state,
    required this.error,
    required this.loading,
    required this.onConfigure,
    required this.onRetry,
  });

  final _ApprovalView? approval;
  final RuntimeAgentState? state;
  final String? error;
  final bool loading;
  final VoidCallback onConfigure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final approval = this.approval;
    final notice = _systemNoticeFor(state, approval, error);
    final showConfigurationActions = notice.contains('tool_unavailable') ||
        notice.contains('needs_configuration') ||
        error != null;
    return ListView(
      children: [
        for (final label in approval?.guardrailLabels ??
            const ['approval_required', 'audit_refs_required'])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _StatusRow(label: label),
          ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surface,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Audit Trace',
                  style: AgentOperatingSystemTokens.labelLg.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Divider(
                  color: AgentOperatingSystemTokens.outlineVariant,
                  height: 20,
                ),
                Text(
                  'Source Message Excerpt'.toUpperCase(),
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  approval?.sourceExcerpt ?? 'No source excerpt reported.',
                  style: AgentOperatingSystemTokens.bodySm,
                ),
                const SizedBox(height: 16),
                Text(
                  'Recent Entity Refs'.toUpperCase(),
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ref in state?.recentEntityRefs ??
                        const <Map<String, Object?>>[])
                      DesktopWorkbenchBadge(
                        label: desktopRuntimeString([
                              ref['title'],
                              ref['entity_id'],
                              ref['entityId'],
                            ]) ??
                            'entity',
                      ),
                    if (state?.recentEntityRefs.isEmpty ?? true)
                      const DesktopWorkbenchBadge(label: 'none'),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Tool Trace Log'.toUpperCase(),
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AgentOperatingSystemTokens.onSurface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      approval?.traceText ??
                          '> guardrail status... not reported',
                      style: AgentOperatingSystemTokens.code.copyWith(
                        color: AgentOperatingSystemTokens.surfaceContainerHigh,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surface,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'System State Notice',
                      style: AgentOperatingSystemTokens.labelLg.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  notice,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
                if (showConfigurationActions) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('desktop_approval_configure'),
                        onPressed: onConfigure,
                        child: const Text('Configure'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('desktop_approval_retry'),
                        onPressed: loading ? null : onRetry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _systemNoticeFor(
  RuntimeAgentState? state,
  _ApprovalView? approval,
  String? error,
) {
  if (error != null) return error;
  if (approval?.needsConfig ?? false) return approval!.systemNotice;
  final approvals =
      state == null ? const <_ApprovalView>[] : _approvalsFromState(state);
  final needsConfig = approvals.where((item) => item.needsConfig).firstOrNull;
  if (needsConfig != null) return needsConfig.systemNotice;
  if (approval?.refused ?? false) return approval!.systemNotice;
  final refused = approvals.where((item) => item.refused).firstOrNull;
  if (refused != null) return refused.systemNotice;
  return approval?.systemNotice ??
      'approval_required: Runtime will apply mutations only after an explicit decision.';
}

final class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: AgentOperatingSystemTokens.secondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: AgentOperatingSystemTokens.code),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CodePair extends StatelessWidget {
  const _CodePair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: AgentOperatingSystemTokens.outline),
          ),
          TextSpan(text: value),
        ],
      ),
      style: AgentOperatingSystemTokens.code.copyWith(
        color: AgentOperatingSystemTokens.onSurfaceVariant,
      ),
    );
  }
}

final class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: AgentOperatingSystemTokens.code.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
