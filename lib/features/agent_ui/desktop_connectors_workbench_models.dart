part of 'desktop_connectors_workbench_page.dart';

List<_ConnectorView> _connectorCatalog(
  BuildContext context,
  RuntimeAgentState? state,
  String? error,
) {
  final text = context.t.chat.operating.desktopWorkbench.connectors;
  final catalog = text.catalog;
  final statuses = text.statuses;
  final runtimeManaged = state != null && error == null;
  final hasWebResearch =
      _stateMentions(state, 'web-research') || runtimeManaged;
  return [
    _ConnectorView(
      id: 'web_research',
      label: catalog.webResearch.label,
      icon: Icons.language_rounded,
      statusLabel: hasWebResearch ? statuses.available : statuses.unknown,
      statusTone: hasWebResearch
          ? _ConnectorStatusTone.available
          : _ConnectorStatusTone.unknown,
      tags: const ['citation_verified'],
      detailTitle: catalog.webResearch.detailTitle,
      detailStatus:
          hasWebResearch ? statuses.available : statuses.capabilityUnknown,
      authTitle: catalog.webResearch.authTitle,
      authMessage: catalog.webResearch.authMessage,
      primaryActionLabel: catalog.webResearch.primaryAction,
      eventLabel: hasWebResearch
          ? catalog.webResearch.eventVerified
          : catalog.webResearch.eventMissing,
      tools: [
        _ConnectorTool(
          catalog.webResearch.tools.search,
          hasWebResearch ? 'available' : 'unknown',
        ),
        _ConnectorTool(
          catalog.webResearch.tools.verify,
          hasWebResearch ? 'available' : 'unknown',
        ),
        _ConnectorTool(
          catalog.webResearch.tools.currentFacts,
          'citation_required',
        ),
      ],
    ),
    _ConnectorView(
      id: 'email',
      label: catalog.email.label,
      icon: Icons.mail_outline_rounded,
      statusLabel: statuses.needsConfig,
      statusTone: _ConnectorStatusTone.needsConfig,
      tags: ['draft_only'],
      detailTitle: catalog.email.detailTitle,
      detailStatus: statuses.emailDraftOnly,
      authTitle: catalog.email.authTitle,
      authMessage: catalog.email.authMessage,
      primaryActionLabel: catalog.email.primaryAction,
      eventLabel: catalog.email.event,
      tools: [
        _ConnectorTool(catalog.email.tools.read, 'tool_unavailable'),
        _ConnectorTool(catalog.email.tools.summarize, 'tool_unavailable'),
        _ConnectorTool(catalog.email.tools.draft, 'available'),
        _ConnectorTool(
          catalog.email.tools.send,
          'approval_required + needs_configuration',
        ),
      ],
    ),
    _ConnectorView(
      id: 'calendar',
      label: catalog.calendar.label,
      icon: Icons.calendar_today_outlined,
      statusLabel: statuses.needsConfig,
      statusTone: _ConnectorStatusTone.needsConfig,
      tags: ['approval_required'],
      detailTitle: catalog.calendar.detailTitle,
      detailStatus: statuses.needsConfiguration,
      authTitle: catalog.calendar.authTitle,
      authMessage: catalog.calendar.authMessage,
      primaryActionLabel: catalog.calendar.primaryAction,
      eventLabel: catalog.calendar.event,
      tools: [
        _ConnectorTool(catalog.calendar.tools.read, 'tool_unavailable'),
        _ConnectorTool(
          catalog.calendar.tools.create,
          'approval_required + needs_configuration',
        ),
        _ConnectorTool(
          catalog.calendar.tools.invite,
          'approval_required + needs_configuration',
        ),
      ],
    ),
    _ConnectorView(
      id: 'files_media',
      label: catalog.filesMedia.label,
      icon: Icons.folder_open_rounded,
      statusLabel: statuses.partial,
      statusTone: _ConnectorStatusTone.partial,
      tags: ['budget_confirmation_required'],
      detailTitle: catalog.filesMedia.detailTitle,
      detailStatus: statuses.partialAvailability,
      authTitle: catalog.filesMedia.authTitle,
      authMessage: catalog.filesMedia.authMessage,
      primaryActionLabel: catalog.filesMedia.primaryAction,
      eventLabel: catalog.filesMedia.event,
      tools: [
        _ConnectorTool(catalog.filesMedia.tools.vaultRead, 'available'),
        _ConnectorTool(
          catalog.filesMedia.tools.documentOcr,
          'budget_confirmation_required',
        ),
        _ConnectorTool(
          catalog.filesMedia.tools.audioTranscription,
          'budget_confirmation_required',
        ),
      ],
    ),
    _ConnectorView(
      id: 'model_provider',
      label: catalog.modelProvider.label,
      icon: Icons.memory_rounded,
      statusLabel: statuses.available,
      statusTone: _ConnectorStatusTone.available,
      tags: [
        'structured_output_verified',
        'Chinese_intent_verified',
        'side_effect_discipline_verified',
      ],
      detailTitle: catalog.modelProvider.detailTitle,
      detailStatus: statuses.runtimeVerified,
      authTitle: catalog.modelProvider.authTitle,
      authMessage: catalog.modelProvider.authMessage,
      primaryActionLabel: catalog.modelProvider.primaryAction,
      eventLabel: catalog.modelProvider.event,
      tools: [
        _ConnectorTool(
            catalog.modelProvider.tools.structuredOutput, 'available'),
        _ConnectorTool(catalog.modelProvider.tools.chineseIntent, 'available'),
        _ConnectorTool(catalog.modelProvider.tools.sideEffect, 'available'),
      ],
    ),
    _ConnectorView(
      id: 'cloudflare_runtime',
      label: catalog.cloudflareRuntime.label,
      icon: Icons.cloud_outlined,
      statusLabel: statuses.runtime,
      statusTone: _ConnectorStatusTone.runtime,
      tags: [
        catalog.cloudflareRuntime.tags.hostedRuntime,
        catalog.cloudflareRuntime.tags.selfManagedSetup,
      ],
      detailTitle: catalog.cloudflareRuntime.detailTitle,
      detailStatus: statuses.hostedRuntime,
      authTitle: catalog.cloudflareRuntime.authTitle,
      authMessage: catalog.cloudflareRuntime.authMessage,
      primaryActionLabel: catalog.cloudflareRuntime.primaryAction,
      eventLabel: catalog.cloudflareRuntime.event,
      tools: [
        _ConnectorTool(
            catalog.cloudflareRuntime.tools.agentRuntime, 'available'),
        _ConnectorTool(
            catalog.cloudflareRuntime.tools.vaultService, 'available'),
        _ConnectorTool(
          catalog.cloudflareRuntime.tools.secretStorage,
          'runtime_secrets_only',
        ),
      ],
    ),
  ];
}

String _lastRuntimeCheckLabel(RuntimeAgentState? state, String notReported) {
  final generatedAtMs = state?.latestContextSnapshot?.generatedAtMs ?? 0;
  if (generatedAtMs > 0) return desktopRuntimeDateLabel(generatedAtMs);
  final lastTurn = state?.conversationTurns.lastOrNull;
  if (lastTurn != null) return desktopRuntimeDateLabel(lastTurn.createdAtMs);
  return notReported;
}

List<String> _auditLabelsFromState(
    RuntimeAgentState? state, String notReported) {
  if (state == null || state.auditRefs.isEmpty) return [notReported];
  return state.auditRefs
      .map(
          (ref) => '${ref['id'] ?? ref['audit_id'] ?? ref['ref'] ?? ''}'.trim())
      .where((label) => label.isNotEmpty)
      .take(4)
      .toList(growable: false);
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

enum _ConnectorStatusTone { available, needsConfig, partial, unknown, runtime }

final class _ConnectorView {
  const _ConnectorView({
    required this.id,
    required this.label,
    required this.icon,
    required this.statusLabel,
    required this.statusTone,
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
  final _ConnectorStatusTone statusTone;
  final List<String> tags;
  final String detailTitle;
  final String detailStatus;
  final String authTitle;
  final String authMessage;
  final String primaryActionLabel;
  final String eventLabel;
  final List<_ConnectorTool> tools;

  Color statusColor(BuildContext context) {
    final colors = context.agentOs;
    return switch (statusTone) {
      _ConnectorStatusTone.needsConfig => const Color(0xFFBA1A1A),
      _ConnectorStatusTone.partial ||
      _ConnectorStatusTone.unknown =>
        colors.onSurfaceVariant,
      _ConnectorStatusTone.available ||
      _ConnectorStatusTone.runtime =>
        colors.secondary,
    };
  }

  Color statusBackground(BuildContext context) {
    final colors = context.agentOs;
    return statusTone == _ConnectorStatusTone.needsConfig
        ? const Color(0xFFFFDAD6)
        : colors.surfaceContainer;
  }

  Color statusBorder(BuildContext context) {
    final colors = context.agentOs;
    return statusTone == _ConnectorStatusTone.needsConfig
        ? const Color(0xFFBA1A1A)
        : colors.outlineVariant;
  }

  Color noticeBackground(BuildContext context) {
    final colors = context.agentOs;
    return statusTone == _ConnectorStatusTone.needsConfig
        ? const Color(0x1AFFDAD6)
        : colors.surfaceContainerLow;
  }
}

final class _ConnectorTool {
  const _ConnectorTool(this.label, this.status);

  final String label;
  final String status;
}
