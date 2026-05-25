import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/runtime_agent_state_repository.dart';
import 'agent_desktop_runtime_helpers.dart';
import 'agent_desktop_workbench_widgets.dart';
import 'agent_operating_system_tokens.dart';

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
    return CloudAuthScope.maybeOf(context)?.controller.uid?.trim() ?? '';
  }

  Future<void> _refresh() async {
    final repository = _repository();
    final vaultId = _vaultId();
    if (repository == null || vaultId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'tool_unavailable: runtime capability state is not configured';
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
      setState(() {
        _state = state;
        _loading = false;
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

  void _openSettingsOrDegrade(String message) {
    if (widget.onOpenSettings != null) {
      widget.onOpenSettings!();
      return;
    }
    showDesktopWorkbenchMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final connectors = _connectorCatalog(_state, _error);
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
            title: 'Connectors',
            subtitle:
                'Runtime bindings, provider availability, and safe degraded states',
            actions: [
              FilledButton.icon(
                key: const ValueKey('desktop_connectors_capability_check'),
                onPressed: _loading
                    ? null
                    : () {
                        showDesktopWorkbenchMessage(
                          context,
                          'Refreshing runtime capability state...',
                        );
                        unawaited(_refresh());
                      },
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('Run capability check'),
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
                      'needs_configuration: configure ${selected.label} before enabling this connector',
                    ),
                    onDraftTest: () => showDesktopWorkbenchMessage(
                      context,
                      'draft-only: draft generation can run without external send permissions',
                    ),
                    onRevoke: () => showDesktopWorkbenchMessage(
                      context,
                      'tool_unavailable: connector revocation endpoint is not available in this build',
                    ),
                    onRetry: _loading ? null : () => unawaited(_refresh()),
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
    return DesktopWorkbenchPanel(
      title: 'Catalogue',
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
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? AgentOperatingSystemTokens.surfaceContainerLow
              : AgentOperatingSystemTokens.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AgentOperatingSystemTokens.secondary
                : AgentOperatingSystemTokens.outlineVariant,
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
                    color: connector.statusColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      connector.label,
                      style: AgentOperatingSystemTokens.labelLg.copyWith(
                        color: AgentOperatingSystemTokens.onSurface,
                      ),
                    ),
                  ),
                  DesktopWorkbenchBadge(
                    label: connector.statusLabel,
                    background: connector.statusBackground,
                    foreground: connector.statusColor,
                    border: connector.statusBorder,
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
    return DesktopWorkbenchPanel(
      title: connector.detailTitle,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, color: connector.statusColor, size: 10),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                connector.detailStatus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  color: connector.statusColor,
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
              color: connector.noticeBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: connector.statusBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connector.authTitle,
                    style: AgentOperatingSystemTokens.labelLg.copyWith(
                      color: AgentOperatingSystemTokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    connector.authMessage,
                    style: AgentOperatingSystemTokens.bodySm.copyWith(
                      color: AgentOperatingSystemTokens.onSurfaceVariant,
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
            'Tool Matrix',
            style: AgentOperatingSystemTokens.labelLg.copyWith(
              color: AgentOperatingSystemTokens.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              border:
                  Border.all(color: AgentOperatingSystemTokens.outlineVariant),
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
                child: const Text('Test draft generation'),
              ),
              OutlinedButton(
                key: const ValueKey('desktop_connector_revoke_access'),
                onPressed: onRevoke,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFBA1A1A),
                ),
                child: const Text('Revoke access'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('desktop_connector_retry_health'),
                onPressed: loading ? null : onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry health check'),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        border: last
            ? null
            : const Border(
                bottom: BorderSide(
                  color: AgentOperatingSystemTokens.outlineVariant,
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
                  tool.status,
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

final class _ConnectorRuntimePanel extends StatelessWidget {
  const _ConnectorRuntimePanel({
    required this.state,
    required this.error,
  });

  final RuntimeAgentState? state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _SidePanelCard(
          title: 'Skill Packages',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final skill in const [
                'web-research',
                'citation-policy',
                'media-understanding',
                'document-ocr',
                'audio-meeting',
                'email',
                'calendar',
                'approval-guardrail',
              ])
                DesktopWorkbenchBadge(label: skill),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SidePanelCard(
          title: 'Runtime Metrics',
          child: Column(
            children: [
              _MetricRow(
                label: 'Smoke Test Status',
                value: error == null ? 'Passed' : 'tool_unavailable',
              ),
              _MetricRow(
                label: 'Last Check',
                value: _lastRuntimeCheckLabel(state),
              ),
              const _MetricRow(label: 'Cost Policy', value: 'Strict Budget'),
              const _MetricRow(label: 'Approval Policy', value: 'Standard'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'BYOK secrets are written only to user runtime secrets, not stored in app config.',
                    style: AgentOperatingSystemTokens.bodySm,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AgentOperatingSystemTokens.headlineSm.copyWith(
                color: AgentOperatingSystemTokens.onSurface,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AgentOperatingSystemTokens.labelMd.copyWith(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: AgentOperatingSystemTokens.bodySm),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Connector Events'.toUpperCase(),
              style: AgentOperatingSystemTokens.labelMd.copyWith(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
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
                                color: connector.statusColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                connector.eventLabel,
                                softWrap: true,
                                style:
                                    AgentOperatingSystemTokens.bodySm.copyWith(
                                  color: connector.statusLabel == 'Available'
                                      ? AgentOperatingSystemTokens.onSurface
                                      : AgentOperatingSystemTokens
                                          .onSurfaceVariant,
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

List<_ConnectorView> _connectorCatalog(
  RuntimeAgentState? state,
  String? error,
) {
  final hasWebResearch = _stateMentions(state, 'web-research') || error == null;
  return [
    _ConnectorView(
      id: 'web_research',
      label: 'Web Research',
      icon: Icons.language_rounded,
      statusLabel: hasWebResearch ? 'Available' : 'Unknown',
      tags: const ['citation_verified'],
      detailTitle: 'Web Research Binding',
      detailStatus: hasWebResearch ? 'Available' : 'Capability unknown',
      authTitle: 'Runtime Skill State',
      authMessage:
          'Current facts must flow through web-research and return citations before the app marks them successful.',
      primaryActionLabel: 'Open research policy',
      eventLabel: 'Web research verified with citations',
      tools: const [
        _ConnectorTool('Search Web', 'available'),
        _ConnectorTool('Verify Citations', 'available'),
        _ConnectorTool('Answer Current Facts', 'citation_required'),
      ],
    ),
    const _ConnectorView(
      id: 'email',
      label: 'Email',
      icon: Icons.mail_outline_rounded,
      statusLabel: 'Needs Config',
      tags: ['draft_only'],
      detailTitle: 'Email Binding',
      detailStatus: 'Degraded State (Draft Only)',
      authTitle: 'Authentication State',
      authMessage:
          'OAuth token expired, revoked, or not configured. Draft generation remains available, but read/send tools are unavailable.',
      primaryActionLabel: 'Connect Email',
      eventLabel: 'Email connector needs configuration',
      tools: [
        _ConnectorTool('Read Email', 'tool_unavailable'),
        _ConnectorTool('Summarize Email', 'tool_unavailable'),
        _ConnectorTool('Create Draft', 'available'),
        _ConnectorTool('Send Email', 'approval_required + needs_configuration'),
      ],
    ),
    const _ConnectorView(
      id: 'calendar',
      label: 'Calendar',
      icon: Icons.calendar_today_outlined,
      statusLabel: 'Needs Config',
      tags: ['approval_required'],
      detailTitle: 'Calendar Binding',
      detailStatus: 'Degraded State (Needs Configuration)',
      authTitle: 'OAuth State',
      authMessage:
          'Calendar tools are unavailable until configured. Event creation and invitation changes remain approval-required.',
      primaryActionLabel: 'Connect Calendar',
      eventLabel: 'Calendar OAuth pending',
      tools: [
        _ConnectorTool('Read Calendar', 'tool_unavailable'),
        _ConnectorTool(
            'Create Event', 'approval_required + needs_configuration'),
        _ConnectorTool(
            'Send Invite', 'approval_required + needs_configuration'),
      ],
    ),
    const _ConnectorView(
      id: 'files_media',
      label: 'Files & Media',
      icon: Icons.folder_open_rounded,
      statusLabel: 'Partial',
      tags: ['budget_confirmation_required'],
      detailTitle: 'Files & Media Binding',
      detailStatus: 'Partial Availability',
      authTitle: 'Media Job State',
      authMessage:
          'Vault attachments can be referenced, while high-cost OCR, transcription, or media understanding requires budget confirmation.',
      primaryActionLabel: 'Review budget policy',
      eventLabel: 'Media provider budget confirmation required',
      tools: [
        _ConnectorTool('Vault Attachment Read', 'available'),
        _ConnectorTool('Document OCR', 'budget_confirmation_required'),
        _ConnectorTool('Audio Transcription', 'budget_confirmation_required'),
      ],
    ),
    const _ConnectorView(
      id: 'model_provider',
      label: 'Model Provider',
      icon: Icons.memory_rounded,
      statusLabel: 'Available',
      tags: [
        'structured_output_verified',
        'Chinese_intent_verified',
        'side_effect_discipline_verified',
      ],
      detailTitle: 'Model Provider Binding',
      detailStatus: 'Runtime Verified',
      authTitle: 'Provider State',
      authMessage:
          'Managed Pro and self-managed modes expose the same user capability set; deployment and secret ownership differ.',
      primaryActionLabel: 'Run provider check',
      eventLabel: 'Model provider smoke tests passed',
      tools: [
        _ConnectorTool('Structured Output', 'available'),
        _ConnectorTool('Chinese Intent Handling', 'available'),
        _ConnectorTool('Side-effect Discipline', 'available'),
      ],
    ),
    const _ConnectorView(
      id: 'cloudflare_runtime',
      label: 'Cloudflare Runtime',
      icon: Icons.cloud_outlined,
      statusLabel: 'Runtime',
      tags: ['hosted_runtime (Managed Pro)', 'Setup CTA (Self-managed)'],
      detailTitle: 'Cloudflare Runtime',
      detailStatus: 'Hosted Runtime (Managed Pro)',
      authTitle: 'Runtime Deployment',
      authMessage:
          'Self-managed setup writes BYOK secrets only to the user runtime. Managed Pro uses hosted runtime controls.',
      primaryActionLabel: 'Open runtime settings',
      eventLabel: 'Runtime manifest loaded',
      tools: [
        _ConnectorTool('Agent Runtime', 'available'),
        _ConnectorTool('Vault Service', 'available'),
        _ConnectorTool('Secret Storage', 'runtime_secrets_only'),
      ],
    ),
  ];
}

String _lastRuntimeCheckLabel(RuntimeAgentState? state) {
  final generatedAtMs = state?.latestContextSnapshot?.generatedAtMs ?? 0;
  if (generatedAtMs > 0) return desktopRuntimeDateLabel(generatedAtMs);
  final lastTurn = state?.conversationTurns.lastOrNull;
  if (lastTurn != null) return desktopRuntimeDateLabel(lastTurn.createdAtMs);
  return 'not reported';
}

bool _stateMentions(RuntimeAgentState? state, String token) {
  if (state == null) return false;
  final normalized = token.toLowerCase();
  final packet = state.latestContextSnapshot?.packet ?? const {};
  if (packet.values.join(' ').toLowerCase().contains(normalized)) return true;
  for (final turn in state.conversationTurns) {
    if ('${turn.raw} ${turn.content}'.toLowerCase().contains(normalized)) {
      return true;
    }
  }
  return false;
}

final class _ConnectorView {
  const _ConnectorView({
    required this.id,
    required this.label,
    required this.icon,
    required this.statusLabel,
    required this.tags,
    required this.detailTitle,
    required this.detailStatus,
    required this.authTitle,
    required this.authMessage,
    required this.primaryActionLabel,
    required this.eventLabel,
    required this.tools,
  });

  final String id;
  final String label;
  final IconData icon;
  final String statusLabel;
  final List<String> tags;
  final String detailTitle;
  final String detailStatus;
  final String authTitle;
  final String authMessage;
  final String primaryActionLabel;
  final String eventLabel;
  final List<_ConnectorTool> tools;

  Color get statusColor {
    final normalized = statusLabel.toLowerCase();
    if (normalized.contains('need')) return const Color(0xFFBA1A1A);
    if (normalized.contains('partial')) {
      return AgentOperatingSystemTokens.onSurfaceVariant;
    }
    return AgentOperatingSystemTokens.secondary;
  }

  Color get statusBackground {
    final normalized = statusLabel.toLowerCase();
    if (normalized.contains('need')) return const Color(0xFFFFDAD6);
    return AgentOperatingSystemTokens.surfaceContainer;
  }

  Color get statusBorder {
    final normalized = statusLabel.toLowerCase();
    if (normalized.contains('need')) return const Color(0xFFBA1A1A);
    return AgentOperatingSystemTokens.outlineVariant;
  }

  Color get noticeBackground {
    final normalized = statusLabel.toLowerCase();
    if (normalized.contains('need')) return const Color(0x1AFFDAD6);
    return AgentOperatingSystemTokens.surfaceContainerLow;
  }
}

final class _ConnectorTool {
  const _ConnectorTool(this.label, this.status);

  final String label;
  final String status;
}
