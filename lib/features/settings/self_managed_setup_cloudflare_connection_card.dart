part of 'self_managed_setup_page.dart';

class _CloudflareConnectionCard extends StatelessWidget {
  const _CloudflareConnectionCard({
    required this.state,
    required this.manualExpanded,
    required this.accountIdController,
    required this.apiTokenController,
    required this.onClose,
    required this.onOAuth,
    required this.onToggleManual,
    required this.onCancel,
    required this.onVerify,
  });

  final SelfManagedSetupState state;
  final bool manualExpanded;
  final TextEditingController accountIdController;
  final TextEditingController apiTokenController;
  final VoidCallback onClose;
  final VoidCallback onOAuth;
  final VoidCallback onToggleManual;
  final VoidCallback onCancel;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _SetupColors.surfaceLowest,
        border: Border.all(color: _SetupColors.surfaceVariant),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CloudflareConnectionHeader(onClose: onClose),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CloudflareInfoBox(),
                  const SizedBox(height: 24),
                  _CloudflareOAuthButton(state: state, onOAuth: onOAuth),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      context.t.settings.selfManagedSetup.cloudflare.oauthHelp,
                      textAlign: TextAlign.center,
                      style: _SetupTextStyles.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1, color: _SetupColors.surfaceVariant),
                  const SizedBox(height: 18),
                  _ManualConfigurationDisclosure(
                    expanded: manualExpanded,
                    accountIdController: accountIdController,
                    apiTokenController: apiTokenController,
                    onToggle: onToggleManual,
                  ),
                  if (state.hasError || state.isCloudflareReady) ...[
                    const SizedBox(height: 18),
                    _ConnectionStatusMessage(state: state),
                  ],
                  const SizedBox(height: 28),
                  _CloudflareConnectionActions(
                    onCancel: onCancel,
                    onVerify: onVerify,
                  ),
                ],
              ),
            ),
            const _CloudflareInsightFooter(),
          ],
        ),
      ),
    );
  }
}

class _CloudflareConnectionHeader extends StatelessWidget {
  const _CloudflareConnectionHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.selfManagedSetup.cloudflare;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _SetupColors.surfaceLow,
        border: Border(
          bottom: BorderSide(color: _SetupColors.surfaceVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.t.app.title,
                    style: const TextStyle(
                      color: _SetupColors.onSurface,
                      fontSize: 20,
                      height: 28 / 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('self_managed_close_setup'),
                  onPressed: onClose,
                  tooltip: t.closeSetup,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _SetupColors.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(t.headerTitle, style: _SetupTextStyles.title),
            const SizedBox(height: 4),
            Text(t.stepIntro, style: _SetupTextStyles.bodySmall),
            const SizedBox(height: 18),
            const _ConnectionProgressBar(),
          ],
        ),
      ),
    );
  }
}

class _ConnectionProgressBar extends StatelessWidget {
  const _ConnectionProgressBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: i == 0
                    ? _SetupColors.secondary
                    : _SetupColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const SizedBox(height: 4),
            ),
          ),
          if (i != 3) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _CloudflareInfoBox extends StatelessWidget {
  const _CloudflareInfoBox();

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.selfManagedSetup.cloudflare;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _SetupColors.surfaceBright,
        border: Border.all(color: _SetupColors.surfaceVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.cloud_sync_rounded,
              color: _SetupColors.secondary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.integrationRequired,
                    style: _SetupTextStyles.label,
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      text: t.integrationDescriptionPrefix,
                      children: [
                        TextSpan(
                          text: t.dashboardApiTokens,
                          style: const TextStyle(
                            color: _SetupColors.secondary,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                    style: _SetupTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(t.ownershipNote, style: _SetupTextStyles.footnote),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualConfigurationDisclosure extends StatelessWidget {
  const _ManualConfigurationDisclosure({
    required this.expanded,
    required this.accountIdController,
    required this.apiTokenController,
    required this.onToggle,
  });

  final bool expanded;
  final TextEditingController accountIdController;
  final TextEditingController apiTokenController;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final setup = context.t.settings.selfManagedSetup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('self_managed_manual_toggle'),
          onTap: onToggle,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    setup.manual.advancedTitle,
                    style: _SetupTextStyles.captionStrong,
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: _SetupColors.onSurfaceVariant,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SetupTextField(
                  fieldKey:
                      const ValueKey('self_managed_cloudflare_account_id'),
                  controller: accountIdController,
                  label: setup.fields.cloudflareAccountId,
                  placeholder: setup.manual.accountIdPlaceholder,
                  hiddenTooltip: setup.manual.tokenHidden,
                  obscure: false,
                ),
                const SizedBox(height: 16),
                _SetupTextField(
                  fieldKey: const ValueKey('self_managed_cloudflare_api_token'),
                  controller: apiTokenController,
                  label: setup.fields.cloudflareApiToken,
                  trailingLabel: setup.manual.apiTokenRequirement,
                  placeholder: setup.manual.apiTokenPlaceholder,
                  hiddenTooltip: setup.manual.tokenHidden,
                ),
                const SizedBox(height: 6),
                Text(
                  setup.manual.footnote,
                  style: _SetupTextStyles.footnote,
                ),
              ],
            ),
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 140),
        ),
      ],
    );
  }
}

class _SetupTextField extends StatelessWidget {
  const _SetupTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.hiddenTooltip,
    this.trailingLabel,
    this.obscure = true,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String placeholder;
  final String hiddenTooltip;
  final String? trailingLabel;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(label, style: _SetupTextStyles.captionStrong)),
            if (trailingLabel != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  trailingLabel!,
                  textAlign: TextAlign.right,
                  style: _SetupTextStyles.caption,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: fieldKey,
          controller: controller,
          obscureText: obscure,
          enableSuggestions: !obscure,
          autocorrect: false,
          maxLines: 1,
          style: _SetupTextStyles.code,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: _SetupTextStyles.code.copyWith(
              color: _SetupColors.onSurfaceVariant.withOpacity(0.54),
            ),
            filled: true,
            fillColor: _SetupColors.surfaceLowest,
            isDense: true,
            suffixIcon: obscure
                ? Tooltip(
                    message: hiddenTooltip,
                    child: const Icon(
                      Icons.visibility_outlined,
                      size: 18,
                      color: _SetupColors.onSurfaceVariant,
                    ),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: _outlineBorder(_SetupColors.surfaceVariant, 8),
            focusedBorder: _outlineBorder(_SetupColors.secondary, 8),
            border: _outlineBorder(_SetupColors.surfaceVariant, 8),
          ),
        ),
      ],
    );
  }
}

class _ConnectionStatusMessage extends StatelessWidget {
  const _ConnectionStatusMessage({required this.state});

  final SelfManagedSetupState state;

  @override
  Widget build(BuildContext context) {
    final success = state.isCloudflareReady && !state.hasError;
    final message = success
        ? context.t.settings.selfManagedSetup.cloudflare.authorizationReady
        : _errorMessage(context, state.errorCode ?? state.statusMessage);
    return DecoratedBox(
      key: const ValueKey('self_managed_connection_status'),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFEFF6FF) : const Color(0xFFFFFBEB),
        border: Border.all(
          color: success ? const Color(0xFFBFDBFE) : const Color(0xFFFDE68A),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              success
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              color: success
                  ? _SetupColors.secondary
                  : _SetupColors.warningForeground,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: success
                      ? _SetupColors.tertiaryFixedVariant
                      : _SetupColors.warningForeground,
                  fontSize: 13,
                  height: 18 / 13,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _errorMessage(BuildContext context, String code) {
    final t = context.t.settings.selfManagedSetup.cloudflare.errors;
    return switch (code) {
      'tool_unavailable:cloudflare_oauth' => t.oauthUnavailable,
      'cloudflare_account_selection_required' => t.accountSelectionRequired,
      'cloudflare_oauth_failed' => t.oauthFailed,
      'missing_cloudflare_account_id' => t.missingAccountId,
      'missing_cloudflare_api_token' => t.missingApiToken,
      _ => code,
    };
  }
}

class _CloudflareConnectionActions extends StatelessWidget {
  const _CloudflareConnectionActions({
    required this.onCancel,
    required this.onVerify,
  });

  final VoidCallback onCancel;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.selfManagedSetup.actions;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 390;
        final cancelButton = TextButton(
          key: const ValueKey('self_managed_cancel_setup'),
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: _SetupColors.onSurfaceVariant,
            minimumSize: Size(stacked ? double.infinity : 0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(t.cancelSetup),
        );
        final verifyButton = FilledButton(
          key: const ValueKey('self_managed_verify_connection'),
          onPressed: onVerify,
          style: FilledButton.styleFrom(
            backgroundColor: _SetupColors.primary,
            foregroundColor: _SetupColors.surfaceLowest,
            minimumSize: Size(stacked ? double.infinity : 0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: _SetupTextStyles.button,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(t.verifyConnection)),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 16),
            ],
          ),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              verifyButton,
              const SizedBox(height: 8),
              cancelButton,
            ],
          );
        }
        return Row(
          children: [
            cancelButton,
            const Spacer(),
            verifyButton,
          ],
        );
      },
    );
  }
}

class _CloudflareInsightFooter extends StatelessWidget {
  const _CloudflareInsightFooter();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _SetupColors.surfaceBright,
        border: Border(
          top: BorderSide(color: _SetupColors.surfaceVariant),
          left: BorderSide(color: _SetupColors.secondary, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.smart_toy_rounded,
              color: _SetupColors.secondary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.t.settings.selfManagedSetup.cloudflare.securityFooter,
                style: _SetupTextStyles.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialHelpLink extends StatelessWidget {
  const _CredentialHelpLink();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        key: const ValueKey('self_managed_help_credentials'),
        onPressed: () {},
        icon: const Icon(Icons.help_outline_rounded, size: 16),
        label: Text(
          context.t.settings.selfManagedSetup.cloudflare.credentialHelp,
        ),
        style: TextButton.styleFrom(
          foregroundColor: _SetupColors.onSurfaceVariant,
          textStyle: _SetupTextStyles.bodySmall,
        ),
      ),
    );
  }
}
