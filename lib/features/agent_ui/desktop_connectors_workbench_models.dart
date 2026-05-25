part of 'desktop_connectors_workbench_page.dart';

List<_ConnectorView> _connectorCatalog(
  RuntimeAgentState? state,
  String? error,
) {
  final runtimeManaged = state != null && error == null;
  final hasWebResearch =
      _stateMentions(state, 'web-research') || runtimeManaged;
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
      eventLabel: hasWebResearch
          ? 'Web research verified with citations'
          : 'Web research capability not reported',
      tools: [
        _ConnectorTool('Search Web', hasWebResearch ? 'available' : 'unknown'),
        _ConnectorTool(
          'Verify Citations',
          hasWebResearch ? 'available' : 'unknown',
        ),
        const _ConnectorTool('Answer Current Facts', 'citation_required'),
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
          'Create Event',
          'approval_required + needs_configuration',
        ),
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

List<String> _auditLabelsFromState(RuntimeAgentState? state) {
  if (state == null || state.auditRefs.isEmpty) return const ['not reported'];
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
    if (normalized.contains('partial') || normalized.contains('unknown')) {
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
