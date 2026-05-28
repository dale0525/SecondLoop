import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/runtime_agent_state_repository.dart';
import '../../core/cloud/runtime_connection_helpers.dart';
import '../../core/cloud/secretary_runtime_conversation_sender.dart';
import '../../i18n/strings.g.dart';
import 'agent_desktop_runtime_helpers.dart';
import 'agent_desktop_workbench_widgets.dart';
import 'agent_operating_system_tokens.dart';

part 'desktop_approvals_workbench_models.dart';
part 'desktop_approvals_workbench_widgets.dart';

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
    final text = context.t.chat.operating.desktopWorkbench.approvals;
    if (repository == null || vaultId.isEmpty) {
      setState(() {
        _loading = false;
        _error = text.messages.stateUnavailable;
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
      final approvals =
          _approvalsFromState(state, _approvalWorkbenchCopy(context));
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
        _error = text.messages.runtimeUnavailable(error: '$error');
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
      final text = context.t.chat.operating.desktopWorkbench.approvals;
      showDesktopWorkbenchMessage(
        context,
        text.messages.cannotSubmit(
          status: approval.status,
          decision: decision,
        ),
      );
      return;
    }
    final sender = _approvalSender();
    final vaultId = _vaultId();
    final text = context.t.chat.operating.desktopWorkbench.approvals;
    if (sender == null || vaultId.isEmpty) {
      showDesktopWorkbenchMessage(
        context,
        text.messages.senderUnavailable,
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
      showDesktopWorkbenchMessage(context, text.messages.decisionSubmitted);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showDesktopWorkbenchMessage(
        context,
        text.messages.runtimeUnavailable(error: '$error'),
      );
    } finally {
      if (mounted) setState(() => _busyApprovalId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workbenchText = context.t.chat.operating.desktopWorkbench;
    final copy = _approvalWorkbenchCopy(context);
    final state = _state;
    final approvals = state == null
        ? const <_ApprovalView>[]
        : _approvalsFromState(state, copy);
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
            title: workbenchText.approvals.title,
            subtitle: workbenchText.approvals.subtitle,
            actions: [
              IconButton.outlined(
                key: const ValueKey('desktop_approvals_refresh'),
                tooltip: workbenchText.approvals.refreshTooltip,
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
                        workbenchText
                            .approvals.messages.requestChangesUnavailable,
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
                        workbenchText.approvals.messages.configureUnavailable,
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
      return approvals
          .where((item) => item.riskLevel == _ApprovalRiskLevel.high)
          .toList(
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
    final text = context.t.chat.operating.desktopWorkbench.approvals.filters;
    final filters = {
      'pending': text.pending,
      'approved': text.approved,
      'rejected': text.rejected,
      'needs_config': text.needsConfig,
      'high_risk': text.highRisk,
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
      final text = context.t.chat.operating.desktopWorkbench.approvals;
      return DesktopWorkbenchEmptyState(
        title: text.emptyTitle,
        message: text.emptyMessage,
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
    final colors = context.agentOs;
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colors.secondary : colors.outlineVariant,
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
                            ? colors.secondary
                            : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  DesktopWorkbenchBadge(
                    label: approval.risk,
                    background: approval.riskLevel == _ApprovalRiskLevel.high
                        ? const Color(0xFFFFDAD6)
                        : colors.surfaceContainerHigh,
                    foreground: approval.riskLevel == _ApprovalRiskLevel.high
                        ? const Color(0xFF93000A)
                        : colors.onSurfaceVariant,
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
                      ? colors.onSurfaceVariant
                      : colors.onSurface,
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
    final colors = context.agentOs;
    final t = context.t.chat.operating.desktopWorkbench.approvals;
    final approval = this.approval;
    if (approval == null) {
      return DesktopWorkbenchPanel(
        title: t.proposedChange,
        child: DesktopWorkbenchEmptyState(
          title: t.selectApproval,
          message: t.selectApprovalMessage,
          icon: Icons.fact_check_outlined,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: colors.surfaceContainerLow,
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
                  DesktopWorkbenchBadge(
                    label: t.risk.prefix(risk: approval.risk),
                  ),
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
                    t.proposedChange,
                    style: AgentOperatingSystemTokens.headlineSm.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ColoredBox(
                          color: colors.surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Text(
                              approval.targetLabel,
                              style:
                                  AgentOperatingSystemTokens.labelMd.copyWith(
                                color: colors.onSurfaceVariant,
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
                                color: colors.secondary,
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
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: colors.secondary,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        approval.reason,
                        style: AgentOperatingSystemTokens.bodySm.copyWith(
                          color: colors.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const ValueKey('desktop_approval_request_changes'),
                  onPressed: onRequestChanges,
                  child: Text(t.requestChanges),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const ValueKey('desktop_approval_reject'),
                  onPressed: busy || !approval.canSubmitDecision('reject')
                      ? null
                      : onReject,
                  child: Text(context.t.common.actions.reject),
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
                      : Text(context.t.common.actions.approve),
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
    final colors = context.agentOs;
    final t = context.t.chat.operating.desktopWorkbench.approvals;
    final approval = this.approval;
    final notice = _systemNoticeFor(
      state,
      approval,
      error,
      _approvalWorkbenchCopy(context),
    );
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
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.auditTrace,
                  style: AgentOperatingSystemTokens.labelLg.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Divider(
                  color: colors.outlineVariant,
                  height: 20,
                ),
                Text(
                  t.sourceMessageExcerpt.toUpperCase(),
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  approval?.sourceExcerpt ?? t.noSourceExcerpt,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t.recentEntityRefs.toUpperCase(),
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: colors.onSurfaceVariant,
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
                            t.entityFallback,
                      ),
                    if (state?.recentEntityRefs.isEmpty ?? true)
                      DesktopWorkbenchBadge(label: t.none),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  t.toolTraceLog.toUpperCase(),
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.onSurface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      approval?.traceText ?? t.traceFallback,
                      style: AgentOperatingSystemTokens.code.copyWith(
                        color: colors.surfaceContainerHigh,
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
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
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
                      t.systemStateNotice,
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
                    color: colors.onSurfaceVariant,
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
                        child: Text(context.t.common.actions.configure),
                      ),
                      OutlinedButton(
                        key: const ValueKey('desktop_approval_retry'),
                        onPressed: loading ? null : onRetry,
                        child: Text(context.t.common.actions.retry),
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
  _ApprovalWorkbenchCopy copy,
) {
  if (error != null) return error;
  if (approval?.needsConfig ?? false) return approval!.systemNotice;
  final approvals = state == null
      ? const <_ApprovalView>[]
      : _approvalsFromState(state, copy);
  final needsConfig = approvals.where((item) => item.needsConfig).firstOrNull;
  if (needsConfig != null) return needsConfig.systemNotice;
  if (approval?.refused ?? false) return approval!.systemNotice;
  final refused = approvals.where((item) => item.refused).firstOrNull;
  if (refused != null) return refused.systemNotice;
  return approval?.systemNotice ?? copy.defaultNotice;
}

final class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: colors.secondary,
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
