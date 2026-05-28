import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/runtime_agent_state_repository.dart';
import '../../core/cloud/runtime_connection_helpers.dart';
import '../../i18n/strings.g.dart';
import 'agent_desktop_runtime_helpers.dart';
import 'agent_desktop_workbench_widgets.dart';
import 'agent_operating_system_tokens.dart';

part 'desktop_connectors_workbench_models.dart';

final class DesktopConnectorsWorkbenchPage extends StatefulWidget {
  const DesktopConnectorsWorkbenchPage({
    this.runtimeAgentStateRepository,
    this.vaultId,
    this.conversationId = 'loop_home',
    this.onOpenSettings,
    super.key,
  });

  final RuntimeAgentStateRepository? runtimeAgentStateRepository;
  final String? vaultId;
  final String conversationId;
  final VoidCallback? onOpenSettings;

  @override
  State<DesktopConnectorsWorkbenchPage> createState() =>
      _DesktopConnectorsWorkbenchPageState();
}

final class _DesktopConnectorsWorkbenchPageState
    extends State<DesktopConnectorsWorkbenchPage> {
  RuntimeAgentState? _state;
  String _selectedConnectorId = 'email';
  String? _error;
  bool _loading = false;
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant DesktopConnectorsWorkbenchPage oldWidget) {
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

  String _vaultId() {
    final explicit = widget.vaultId?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final selfManagedVaultId =
        cachedSelfManagedRuntimeConnection()?.profile.vaultId.trim() ?? '';
    if (selfManagedVaultId.isNotEmpty) return selfManagedVaultId;
    return CloudAuthScope.maybeOf(context)?.controller.uid?.trim() ?? '';
  }

  Future<void> _refresh({bool announceUnavailable = false}) async {
    final needsSavedRuntimeConnection =
        widget.runtimeAgentStateRepository == null &&
            (widget.vaultId?.trim().isEmpty ?? true);
    if (needsSavedRuntimeConnection) {
      await loadRuntimeConnectionSafely();
      if (!mounted) return;
    }
    final repository = _repository();
    final vaultId = _vaultId();
    if (repository == null || vaultId.isEmpty) {
      final message =
          context.t.chat.operating.desktopWorkbench.connectors.unavailableState;
      setState(() {
        _loading = false;
        _error = message;
        _state = RuntimeAgentState.empty(
          vaultId: vaultId,
          conversationId: widget.conversationId,
        );
      });
      if (announceUnavailable && mounted) {
        showDesktopWorkbenchMessage(context, message);
      }
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
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final message = context.t.chat.operating.desktopWorkbench.connectors
          .runtimeUnavailable(error: '$error');
      setState(() {
        _loading = false;
        _error = message;
        _state ??= RuntimeAgentState.empty(
          vaultId: vaultId,
          conversationId: widget.conversationId,
        );
      });
      if (announceUnavailable) {
        showDesktopWorkbenchMessage(context, message);
      }
    }
  }

  void _openSettingsOrDegrade(String message) {
    if (widget.onOpenSettings != null) {
      widget.onOpenSettings!();
      return;
    }
    showDesktopWorkbenchMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.desktopWorkbench.connectors;
    final connectors = _connectorCatalog(context, _state, _error);
    final selected = connectors
            .where((connector) => connector.id == _selectedConnectorId)
            .firstOrNull ??
        connectors.first;

    return DesktopWorkbenchPageShell(
      key: const ValueKey('desktop_connectors_workbench_page'),
      maxWidth: 1280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopWorkbenchHeader(
            title: t.title,
            subtitle: t.subtitle,
            actions: [
              FilledButton.icon(
                key: const ValueKey('desktop_connectors_capability_check'),
                onPressed: _loading
                    ? null
                    : () {
                        if (_repository() == null || _vaultId().isEmpty) {
                          showDesktopWorkbenchMessage(
                            context,
                            t.unavailableState,
                          );
                        } else {
                          showDesktopWorkbenchMessage(
                            context,
                            t.refreshing,
                          );
                        }
                        unawaited(_refresh(announceUnavailable: true));
                      },
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: Text(t.runCapabilityCheck),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: _ConnectorCatalogue(
                    connectors: connectors,
                    selectedId: selected.id,
                    onSelect: (connector) => setState(
                      () => _selectedConnectorId = connector.id,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 5,
                  child: _ConnectorDetail(
                    connector: selected,
                    loading: _loading,
                    onConnect: () => _openSettingsOrDegrade(
                      t.needsConfiguration(connector: selected.label),
                    ),
                    onDraftTest: () => showDesktopWorkbenchMessage(
                      context,
                      t.draftOnly,
                    ),
                    onRevoke: () => showDesktopWorkbenchMessage(
                      context,
                      t.revokeUnavailable,
                    ),
                    onRetry: _loading
                        ? null
                        : () => unawaited(
                              _refresh(announceUnavailable: true),
                            ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 3,
                  child: _ConnectorRuntimePanel(
                    state: _state,
                    error: _error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 156,
            child: _ConnectorTimeline(connectors: connectors),
          ),
        ],
      ),
    );
  }
}

final class _ConnectorCatalogue extends StatelessWidget {
  const _ConnectorCatalogue({
    required this.connectors,
    required this.selectedId,
    required this.onSelect,
  });

  final List<_ConnectorView> connectors;
  final String selectedId;
  final ValueChanged<_ConnectorView> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = context.t.chat.operating.desktopWorkbench.connectors;
    return DesktopWorkbenchPanel(
      title: text.catalogue,
      trailing: const Icon(Icons.filter_list_rounded, size: 18),
      padding: const EdgeInsets.all(16),
      child: ListView.separated(
        itemCount: connectors.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final connector = connectors[index];
          return _ConnectorCard(
            key: ValueKey('desktop_connector_${connector.id}'),
            connector: connector,
            selected: connector.id == selectedId,
            onTap: () => onSelect(connector),
          );
        },
      ),
    );
  }
}

final class _ConnectorCard extends StatelessWidget {
  const _ConnectorCard({
    required this.connector,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _ConnectorView connector;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colors.surfaceContainerLow : colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colors.secondary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    connector.icon,
                    color: connector.statusColor(context),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      connector.label,
                      style: AgentOperatingSystemTokens.labelLg.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  DesktopWorkbenchBadge(
                    label: connector.statusLabel,
                    background: connector.statusBackground(context),
                    foreground: connector.statusColor(context),
                    border: connector.statusBorder(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final tag in connector.tags)
                    DesktopWorkbenchBadge(label: tag),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ConnectorDetail extends StatelessWidget {
  const _ConnectorDetail({
    required this.connector,
    required this.loading,
    required this.onConnect,
    required this.onDraftTest,
    required this.onRevoke,
    required this.onRetry,
  });

  final _ConnectorView connector;
  final bool loading;
  final VoidCallback onConnect;
  final VoidCallback onDraftTest;
  final VoidCallback onRevoke;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    final t = context.t.chat.operating.desktopWorkbench.connectors;
    return DesktopWorkbenchPanel(
      title: connector.detailTitle,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              color: connector.statusColor(context),
              size: 10,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                connector.detailStatus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  color: connector.statusColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: connector.noticeBackground(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: connector.statusBorder(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connector.authTitle,
                    style: AgentOperatingSystemTokens.labelLg.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    connector.authMessage,
                    style: AgentOperatingSystemTokens.bodySm.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: ValueKey('desktop_connector_primary_${connector.id}'),
                    onPressed: onConnect,
                    child: Text(connector.primaryActionLabel),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            t.toolMatrix,
            style: AgentOperatingSystemTokens.labelLg.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < connector.tools.length; i++)
                  _ConnectorToolRow(
                    tool: connector.tools[i],
                    last: i == connector.tools.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                key: const ValueKey('desktop_connector_test_draft'),
                onPressed: onDraftTest,
                child: Text(t.testDraftGeneration),
              ),
              OutlinedButton(
                key: const ValueKey('desktop_connector_revoke_access'),
                onPressed: onRevoke,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFBA1A1A),
                ),
                child: Text(t.revokeAccess),
              ),
              OutlinedButton.icon(
                key: const ValueKey('desktop_connector_retry_health'),
                onPressed: loading ? null : onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(t.retryHealthCheck),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ConnectorToolRow extends StatelessWidget {
  const _ConnectorToolRow({
    required this.tool,
    required this.last,
  });

  final _ConnectorTool tool;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                  color: colors.outlineVariant,
                ),
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(tool.label, style: AgentOperatingSystemTokens.bodySm),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _connectorCapabilityLabel(context, tool.status),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: desktopStatusColor(tool.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _connectorCapabilityLabel(BuildContext context, String status) {
  final labels =
      context.t.chat.operating.desktopWorkbench.connectors.capabilityLabels;
  final parts = status
      .split('+')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length > 1) {
    return parts
        .map((part) => _connectorCapabilityLabel(context, part))
        .join(labels.separator);
  }
  return switch (status.trim().toLowerCase()) {
    'available' => labels.available,
    'unknown' => labels.unknown,
    'tool_unavailable' => labels.toolUnavailable,
    'approval_required' => labels.approvalRequired,
    'needs_configuration' => labels.needsConfiguration,
    'citation_required' => labels.citationRequired,
    'budget_confirmation_required' => labels.budgetConfirmationRequired,
    'runtime_secrets_only' => labels.runtimeSecretsOnly,
    _ => labels.runtimeCapability,
  };
}

final class _ConnectorRuntimePanel extends StatelessWidget {
  const _ConnectorRuntimePanel({
    required this.state,
    required this.error,
  });

  final RuntimeAgentState? state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    final t = context.t.chat.operating.desktopWorkbench.connectors;
    return ListView(
      children: [
        _SidePanelCard(
          title: t.skillPackages,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final skill in [
                t.skillLabels.webResearch,
                t.skillLabels.citationPolicy,
                t.skillLabels.mediaUnderstanding,
                t.skillLabels.documentOcr,
                t.skillLabels.audioMeeting,
                t.skillLabels.email,
                t.skillLabels.calendar,
                t.skillLabels.approvalGuardrail,
              ])
                DesktopWorkbenchBadge(label: skill),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SidePanelCard(
          title: t.runtimeMetrics,
          child: Column(
            children: [
              _MetricRow(
                label: t.smokeTestStatus,
                value: error == null
                    ? t.passed
                    : t.capabilityLabels.toolUnavailable,
              ),
              _MetricRow(
                label: t.lastCheck,
                value: _lastRuntimeCheckLabel(state, t.notReported),
              ),
              _MetricRow(label: t.costPolicy, value: t.strictBudget),
              _MetricRow(label: t.approvalPolicy, value: t.standard),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SidePanelCard(
          title: t.auditTrail,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in _auditLabelsFromState(state, t.notReported))
                DesktopWorkbenchBadge(label: label),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.byokSecretsNotice,
                    style: AgentOperatingSystemTokens.bodySm.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final class _SidePanelCard extends StatelessWidget {
  const _SidePanelCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return DecoratedBox(
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
              title,
              style: AgentOperatingSystemTokens.headlineSm.copyWith(
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

final class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AgentOperatingSystemTokens.labelMd.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: AgentOperatingSystemTokens.bodySm.copyWith(
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

final class _ConnectorTimeline extends StatelessWidget {
  const _ConnectorTimeline({required this.connectors});

  final List<_ConnectorView> connectors;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return DecoratedBox(
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
            Text(
              context.t.chat.operating.desktopWorkbench.connectors
                  .recentConnectorEvents
                  .toUpperCase(),
              style: AgentOperatingSystemTokens.labelMd.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    for (final connector in connectors)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 250),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Icon(
                                Icons.circle,
                                size: 8,
                                color: connector.statusColor(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                connector.eventLabel,
                                softWrap: true,
                                style:
                                    AgentOperatingSystemTokens.bodySm.copyWith(
                                  color: connector.statusTone ==
                                          _ConnectorStatusTone.available
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
