part of 'self_managed_setup_sections.dart';

class _CloudflareAuthorizationCard extends StatelessWidget {
  const _CloudflareAuthorizationCard();

  static const _items = [
    _SafetyItem(
      Icons.construction_rounded,
      'Setup helper only',
      'Tokens are used solely for deployment automation.',
    ),
    _SafetyItem(
      Icons.no_accounts_rounded,
      'Not saved as business config',
      'Credential lifetime limited to active session.',
    ),
    _SafetyItem(
      Icons.history_rounded,
      'Can be revoked after deployment',
      'Remove API tokens once workers are live.',
    ),
    _SafetyItem(
      Icons.folder_shared_rounded,
      'Resources owned by you',
      'Workers and KV stores stay in your account.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _SetupCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.security_rounded, color: _SetupColors.secondary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cloudflare Authorization',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _SetupTextStyles.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 620;
              final itemWidth = twoColumns
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final item in _items)
                    SizedBox(
                      width: itemWidth,
                      child: _SafetyTile(item: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SafetyItem {
  const _SafetyItem(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

class _SafetyTile extends StatelessWidget {
  const _SafetyTile({required this.item});

  final _SafetyItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _SetupColors.surface,
        border: Border.all(color: _SetupColors.outlineVariant),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, size: 20, color: _SetupColors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: _SetupTextStyles.label),
                  const SizedBox(height: 2),
                  Text(item.body, style: _SetupTextStyles.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityVerificationCard extends StatelessWidget {
  const _CapabilityVerificationCard({required this.verification});

  final ModelCapabilityVerificationResult? verification;

  @override
  Widget build(BuildContext context) {
    return _SetupCard(
      padding: EdgeInsets.zero,
      clip: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Capability Verification',
                    style: _SetupTextStyles.title,
                  ),
                ),
                _VerificationRunChip(verification: verification),
              ],
            ),
          ),
          const Divider(height: 1, color: _SetupColors.outlineVariant),
          for (final spec in _capabilitySpecs)
            _CapabilityRow(
              key: ValueKey('self_managed_capability_${spec.code}'),
              spec: spec,
              verification: verification,
            ),
        ],
      ),
    );
  }
}

class _VerificationRunChip extends StatelessWidget {
  const _VerificationRunChip({required this.verification});

  final ModelCapabilityVerificationResult? verification;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _SetupColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          verification == null ? 'Not run yet' : 'Last run: latest',
          style: const TextStyle(
            color: _SetupColors.onSurfaceVariant,
            fontSize: 11,
            height: 14 / 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    super.key,
    required this.spec,
    required this.verification,
  });

  final _CapabilitySpec spec;
  final ModelCapabilityVerificationResult? verification;

  @override
  Widget build(BuildContext context) {
    final presentation = _CapabilityPresentation.from(spec, verification);
    return DecoratedBox(
      decoration: BoxDecoration(color: presentation.background),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              presentation.icon,
              color: presentation.iconColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                spec.label,
                style: TextStyle(
                  color: presentation.foreground,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: presentation.emphasized
                      ? FontWeight.w700
                      : FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                presentation.status,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: presentation.statusColor,
                  fontSize: 11,
                  height: 14 / 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuntimeManifestCard extends StatelessWidget {
  const _RuntimeManifestCard({required this.manifest});

  final CloudRuntimeManifest? manifest;

  @override
  Widget build(BuildContext context) {
    final fields = [
      _ManifestField(
        'Endpoint URL',
        manifest?.apiBaseUrl ?? 'pending',
        accent: manifest?.apiBaseUrl.isNotEmpty == true,
      ),
      _ManifestField('Vault Binding', manifest?.vaultBinding ?? 'pending'),
      _ManifestField(
        'Skill Availability Report',
        _skillAvailabilityLabel(manifest),
      ),
      _ManifestField(
        'Provider Cost Owner',
        manifest?.providerCostOwner ?? 'pending',
        strong: manifest?.providerCostOwner != null,
      ),
    ];
    return _SetupCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Runtime Manifest', style: _SetupTextStyles.title),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 620;
              final itemWidth = twoColumns
                  ? (constraints.maxWidth - 32) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 32,
                runSpacing: 16,
                children: [
                  for (final field in fields)
                    SizedBox(
                      width: itemWidth,
                      child: _ManifestFieldView(field: field),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _skillAvailabilityLabel(CloudRuntimeManifest? manifest) {
    final skills = manifest?.skills ?? const <CloudRuntimeSkillAvailability>[];
    if (skills.isEmpty) return 'pending';
    final active = skills
        .where((skill) =>
            skill.status == 'ready' ||
            skill.status == 'active' ||
            skill.status == 'available')
        .length;
    return '$active/${skills.length} active';
  }
}

class _RuntimeManagementCard extends StatelessWidget {
  const _RuntimeManagementCard({
    required this.state,
    required this.isBusy,
    required this.onUninstallRuntime,
  });

  final SelfManagedSetupState state;
  final bool isBusy;
  final Future<void> Function() onUninstallRuntime;

  @override
  Widget build(BuildContext context) {
    final uninstalled = state.isUninstalled;
    return _SetupCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            title: 'Runtime Management',
            subtitle: 'Remove the self-managed runtime from your account.',
          ),
          const SizedBox(height: 12),
          if (uninstalled)
            const _InlineNote(
              icon: Icons.check_circle_outline_rounded,
              text: 'Self-managed runtime connection removed.',
            )
          else ...[
            const _InlineNote(
              icon: Icons.warning_amber_rounded,
              text:
                  'This removes workers, bindings, and runtime secrets owned by your Cloudflare account.',
              tone: _InlineNoteTone.warning,
            ),
            if (state.hasError) ...[
              const SizedBox(height: 10),
              _InlineNote(
                icon: Icons.error_outline_rounded,
                text: state.errorCode ?? state.statusMessage,
                tone: _InlineNoteTone.warning,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('self_managed_uninstall_runtime'),
              onPressed: isBusy ? null : () => _confirmUninstall(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _SetupColors.warningForeground,
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                side: const BorderSide(
                  color: _SetupColors.warningForeground,
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(isBusy ? 'Uninstalling...' : 'Uninstall runtime'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmUninstall(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _UninstallRuntimeDialog(),
    );
    if (confirmed == true) {
      await onUninstallRuntime();
    }
  }
}

class _UninstallRuntimeDialog extends StatelessWidget {
  const _UninstallRuntimeDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('self_managed_confirm_uninstall_dialog'),
      title: const Text('Uninstall self-managed runtime?'),
      content: const Text(
        'SecondLoop will use your session Cloudflare credentials to remove the runtime resources and then clear the saved connection.',
      ),
      actions: [
        TextButton(
          key: const ValueKey('self_managed_cancel_uninstall'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('self_managed_confirm_uninstall'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Uninstall'),
        ),
      ],
    );
  }
}

class _ManifestField {
  const _ManifestField(
    this.label,
    this.value, {
    this.accent = false,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool accent;
  final bool strong;
}

class _ManifestFieldView extends StatelessWidget {
  const _ManifestFieldView({required this.field});

  final _ManifestField field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label.toUpperCase(), style: _SetupTextStyles.caption),
        const SizedBox(height: 4),
        Text(
          field.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                field.accent ? _SetupColors.secondary : _SetupColors.onSurface,
            fontSize: 13,
            height: 18 / 13,
            fontWeight: field.strong ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _SetupTextStyles.title),
        const SizedBox(height: 4),
        Text(subtitle, style: _SetupTextStyles.bodySmall),
      ],
    );
  }
}

enum _InlineNoteTone { info, warning }

class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.text,
    this.tone = _InlineNoteTone.info,
  });

  final IconData icon;
  final String text;
  final _InlineNoteTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == _InlineNoteTone.warning
        ? _SetupColors.warningForeground
        : _SetupColors.tertiaryFixedVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              height: 18 / 13,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor = _SetupColors.surfaceLowest,
    this.clip = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: _SetupColors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        clipBehavior: clip,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class _CapabilitySpec {
  const _CapabilitySpec(this.code, this.label, this.successLabel);

  final String code;
  final String label;
  final String successLabel;
}

const _capabilitySpecs = [
  _CapabilitySpec(
    ModelCapabilityRequiredChecks.structuredOutput,
    'Structured Output',
    'JSON_MODE=VALIDATED',
  ),
  _CapabilitySpec(
    ModelCapabilityRequiredChecks.secretaryMetadata,
    'Secretary Metadata',
    'SCHEMA_V4_PASS',
  ),
  _CapabilitySpec(
    ModelCapabilityRequiredChecks.toolProposalDiscipline,
    'Tool Proposal Discipline',
    'ZERO_SHOT_ACCURACY=98%',
  ),
  _CapabilitySpec(
    ModelCapabilityRequiredChecks.multimodalUnderstanding,
    'Multimodal Understanding',
    'IMAGE_OCR_READY',
  ),
  _CapabilitySpec(
    ModelCapabilityRequiredChecks.chineseIntentHandling,
    'Chinese Intent Handling',
    'LANG_ISO_ZH_TRUE',
  ),
  _CapabilitySpec(
    ModelCapabilityRequiredChecks.contextWindowLatency,
    'Context Window + Latency',
    '128K_OK | 240MS_TTFT',
  ),
  _CapabilitySpec(
    ModelCapabilityRequiredChecks.clarificationBehavior,
    'Clarification Behavior',
    'AMBIGUITY_TRAP_PASSED',
  ),
  _CapabilitySpec(
    ModelCapabilityRequiredChecks.sideEffectDiscipline,
    'Side-effect Discipline',
    'SIDE_EFFECTS_GATED',
  ),
];

class _CapabilityPresentation {
  const _CapabilityPresentation({
    required this.icon,
    required this.iconColor,
    required this.status,
    required this.statusColor,
    required this.foreground,
    required this.background,
    this.emphasized = false,
  });

  final IconData icon;
  final Color iconColor;
  final String status;
  final Color statusColor;
  final Color foreground;
  final Color background;
  final bool emphasized;

  static _CapabilityPresentation from(
    _CapabilitySpec spec,
    ModelCapabilityVerificationResult? verification,
  ) {
    ModelCapabilityCheckResult? check;
    for (final candidate
        in verification?.checks ?? const <ModelCapabilityCheckResult>[]) {
      if (candidate.code == spec.code) {
        check = candidate;
        break;
      }
    }
    if (verification == null || check == null) {
      return const _CapabilityPresentation(
        icon: Icons.pending_outlined,
        iconColor: _SetupColors.outline,
        status: 'PENDING',
        statusColor: _SetupColors.onSurfaceVariant,
        foreground: _SetupColors.onSurface,
        background: Colors.transparent,
      );
    }
    if (check.passed) {
      return _CapabilityPresentation(
        icon: Icons.check_circle_rounded,
        iconColor: _SetupColors.success,
        status: spec.successLabel,
        statusColor: _SetupColors.onSurfaceVariantMuted,
        foreground: _SetupColors.onSurface,
        background: Colors.transparent,
      );
    }
    return _CapabilityPresentation(
      icon: Icons.pending_rounded,
      iconColor: _SetupColors.warning,
      status: _failureLabel(check),
      statusColor: _SetupColors.warningForeground,
      foreground: _SetupColors.warningText,
      background: _SetupColors.warningBackground,
      emphasized: true,
    );
  }

  static String _failureLabel(ModelCapabilityCheckResult check) {
    final raw = check.failureCode ?? check.code;
    if (raw.trim().isEmpty) return 'RETRY_REQUIRED';
    return raw.trim().replaceAll('-', '_').toUpperCase();
  }
}

final class _SetupTextStyles {
  const _SetupTextStyles._();

  static const title = TextStyle(
    color: _SetupColors.onSurface,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const label = TextStyle(
    color: _SetupColors.onSurface,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const bodySmall = TextStyle(
    color: _SetupColors.onSurfaceVariant,
    fontSize: 13,
    height: 18 / 13,
    letterSpacing: 0,
  );

  static const caption = TextStyle(
    color: _SetupColors.onSurfaceVariant,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
}

final class _SetupColors {
  const _SetupColors._();

  static const primary = Color(0xFF000000);
  static const secondary = Color(0xFF0051D5);
  static const surface = Color(0xFFF7F9FB);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFF2F4F6);
  static const surfaceContainer = Color(0xFFECEEF0);
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF45464D);
  static const onSurfaceVariantMuted = Color(0x9945464D);
  static const outline = Color(0xFF76777D);
  static const outlineVariant = Color(0xFFC6C6CD);
  static const tertiaryFixedVariant = Color(0xFF38485D);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const warningForeground = Color(0xFFB45309);
  static const warningText = Color(0xFF78350F);
  static const warningBackground = Color(0x4DFFFBEB);
}

OutlineInputBorder _outlineBorder(Color color) {
  return OutlineInputBorder(
    borderSide: BorderSide(color: color),
    borderRadius: BorderRadius.circular(2),
  );
}
