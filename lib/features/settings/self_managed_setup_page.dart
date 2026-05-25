import 'package:flutter/material.dart';

import '../../core/cloud/self_managed_setup_controller.dart';
import '../../core/cloud/self_managed_setup_models.dart';
import '../../ui/sl_tokens.dart';
import 'self_managed_setup_sections.dart';

class SelfManagedSetupPage extends StatefulWidget {
  const SelfManagedSetupPage({
    super.key,
    this.controller,
    this.initialCloudflareAccountLabel = 'personal-vault',
  });

  final SelfManagedSetupController? controller;
  final String initialCloudflareAccountLabel;

  @override
  State<SelfManagedSetupPage> createState() => _SelfManagedSetupPageState();
}

class _SelfManagedSetupPageState extends State<SelfManagedSetupPage> {
  late final SelfManagedSetupController _controller;
  late final TextEditingController _cloudflareAccountController;
  final _cloudflareAccountIdController = TextEditingController();
  final _cloudflareApiTokenController = TextEditingController();
  final _providerController = TextEditingController(text: 'openai');
  final _apiKeyController = TextEditingController();
  final _embeddingApiKeyController = TextEditingController();
  final _multimodalApiKeyController = TextEditingController();
  var _busy = false;
  var _manualExpanded = false;
  var _showSetupDetails = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SelfManagedSetupController();
    _cloudflareAccountController = TextEditingController(
      text: widget.initialCloudflareAccountLabel,
    );
  }

  @override
  void dispose() {
    _cloudflareAccountController.dispose();
    _cloudflareAccountIdController.dispose();
    _cloudflareApiTokenController.dispose();
    _providerController.dispose();
    _apiKeyController.dispose();
    _embeddingApiKeyController.dispose();
    _multimodalApiKeyController.dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _startCloudflareOAuth() {
    setState(() => _showSetupDetails = false);
    _controller.reportCloudflareOAuthUnavailable();
  }

  void _verifyCloudflareConnection() {
    if (!_manualExpanded) {
      _startCloudflareOAuth();
      return;
    }
    final ok = _controller.prepareManualCloudflareAuthorization(
      accountId: _cloudflareAccountIdController.text,
      apiToken: _cloudflareApiTokenController.text,
    );
    if (!ok) return;
    _cloudflareAccountController.text =
        _cloudflareAccountIdController.text.trim();
    setState(() => _showSetupDetails = true);
  }

  Future<void> _runSetup() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _controller.deploy(
      SelfManagedSetupRequest(
        cloudflareAccountLabel: _cloudflareAccountController.text.trim(),
        provider: _providerController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        embeddingApiKey: _embeddingApiKeyController.text.trim(),
        multimodalApiKey: _multimodalApiKeyController.text.trim(),
        cloudflareAuthorizationMethod:
            _cloudflareAccountIdController.text.trim().isNotEmpty ||
                    _cloudflareApiTokenController.text.trim().isNotEmpty
                ? SelfManagedCloudflareAuthorizationMethod.manual
                : SelfManagedCloudflareAuthorizationMethod.oauth,
        cloudflareAccountId: _cloudflareAccountIdController.text.trim(),
        cloudflareApiToken: _cloudflareApiTokenController.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final state = _controller.state;
        final shouldShowDetails =
            _showSetupDetails || state.isCloudflareReady || state.isReady;
        return Theme(
          data: _selfManagedSetupTheme(context),
          child: Scaffold(
            key: const ValueKey('self_managed_setup_root'),
            backgroundColor: _SetupColors.surface,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 48,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CloudflareConnectionCard(
                                state: state,
                                manualExpanded: _manualExpanded,
                                accountIdController:
                                    _cloudflareAccountIdController,
                                apiTokenController:
                                    _cloudflareApiTokenController,
                                onClose: () => Navigator.of(context).maybePop(),
                                onOAuth: _startCloudflareOAuth,
                                onToggleManual: () {
                                  setState(
                                    () => _manualExpanded = !_manualExpanded,
                                  );
                                },
                                onCancel: () =>
                                    Navigator.of(context).maybePop(),
                                onVerify: _verifyCloudflareConnection,
                              ),
                              const SizedBox(height: 24),
                              const _CredentialHelpLink(),
                              if (shouldShowDetails) ...[
                                const SizedBox(height: 24),
                                SelfManagedSetupSections(
                                  controller: _controller,
                                  cloudflareAccountController:
                                      _cloudflareAccountController,
                                  providerController: _providerController,
                                  apiKeyController: _apiKeyController,
                                  embeddingApiKeyController:
                                      _embeddingApiKeyController,
                                  multimodalApiKeyController:
                                      _multimodalApiKeyController,
                                  isBusy: _busy,
                                  onWriteSecrets: _runSetup,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  ThemeData _selfManagedSetupTheme(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context).copyWith(
      background: _SetupColors.surface,
      surface: _SetupColors.surfaceLowest,
      surface2: _SetupColors.surfaceContainer,
      border: _SetupColors.outlineVariant,
      borderSubtle: _SetupColors.outlineVariant,
      ring: _SetupColors.secondary,
    );
    return theme.copyWith(
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: _SetupColors.secondary,
        onPrimary: _SetupColors.surfaceLowest,
        surface: _SetupColors.surface,
        onSurface: _SetupColors.onSurface,
        onSurfaceVariant: _SetupColors.onSurfaceVariant,
        outline: _SetupColors.outline,
        outlineVariant: _SetupColors.outlineVariant,
      ),
      scaffoldBackgroundColor: _SetupColors.surface,
      extensions: [
        ...theme.extensions.values.where((extension) => extension is! SlTokens),
        tokens,
      ],
    );
  }
}

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
                  FilledButton.icon(
                    key: const ValueKey('self_managed_cloudflare_oauth'),
                    onPressed: onOAuth,
                    icon: const Icon(Icons.link_rounded, size: 20),
                    label: const Text('Connect Cloudflare Account'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: _SetupColors.secondary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: _SetupTextStyles.button,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Authorize SecondLoop via OAuth for automated workspace configuration.',
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
                const Expanded(
                  child: Text(
                    'SecondLoop',
                    style: TextStyle(
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
                  tooltip: 'Close setup',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _SetupColors.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Infrastructure Connection',
              style: _SetupTextStyles.title,
            ),
            const SizedBox(height: 4),
            const Text(
              'Step 1 of 4: Link your edge provider to establish the secure vault environment.',
              style: _SetupTextStyles.bodySmall,
            ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _SetupColors.surfaceBright,
        border: Border.all(color: _SetupColors.surfaceVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_sync_rounded,
              color: _SetupColors.secondary,
              size: 22,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cloudflare Integration Required',
                    style: _SetupTextStyles.label,
                  ),
                  SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      text:
                          'SecondLoop utilizes Cloudflare Workers to manage your private vault operations securely at the edge. You can find manual credentials in your ',
                      children: [
                        TextSpan(
                          text: 'Cloudflare Dashboard -> API Tokens',
                          style: TextStyle(color: _SetupColors.secondary),
                        ),
                        TextSpan(text: '.'),
                      ],
                    ),
                    style: _SetupTextStyles.bodySmall,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'All infrastructure (D1, KV, R2) and Agent runtimes remain under your ownership. Provider costs are billed directly to your account.',
                    style: _SetupTextStyles.footnote,
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
                const Expanded(
                  child: Text(
                    'Advanced: Manual Configuration',
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
                  label: 'Cloudflare Account ID',
                  placeholder: 'e.g., 9a7806061c88ada191ed06f989cc3dac',
                  obscure: false,
                ),
                const SizedBox(height: 16),
                _SetupTextField(
                  fieldKey: const ValueKey('self_managed_cloudflare_api_token'),
                  controller: apiTokenController,
                  label: 'API Token',
                  trailingLabel: "Requires 'Workers: Edit' (Least Privilege)",
                  placeholder: '••••••••••••••••••••••••••••••••',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Setup helper only. Tokens are used solely for deployment automation and are not saved as business config. Credential lifetime limited to active session.',
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
    this.trailingLabel,
    this.obscure = true,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String placeholder;
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
                ? const Tooltip(
                    message: 'Token stays hidden',
                    child: Icon(
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
        ? 'Manual credentials are ready for the setup helper. Deployment will verify them against Cloudflare before saving runtime metadata.'
        : _errorMessage(state.errorCode ?? state.statusMessage);
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

  String _errorMessage(String code) {
    return switch (code) {
      'tool_unavailable:cloudflare_oauth' =>
        'Cloudflare OAuth handoff is not available in this local build yet. Use manual configuration or retry after the setup helper is configured.',
      'missing_cloudflare_account_id' =>
        'Enter the Cloudflare account id before verifying manual setup.',
      'missing_cloudflare_api_token' =>
        'Enter a session-scoped Cloudflare API token before verifying manual setup.',
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
          child: const Text('Cancel Setup'),
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text('Verify Connection')),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 16),
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
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: _SetupColors.surfaceBright,
        border: Border(
          top: BorderSide(color: _SetupColors.surfaceVariant),
          left: BorderSide(color: _SetupColors.secondary, width: 2),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.smart_toy_rounded,
              color: _SetupColors.secondary,
              size: 22,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cloudflare management authorization is used only for setup helper and is not stored as a persistent business configuration. LLM/BYOK secrets are written directly to your own Cloudflare runtime secrets; the App does not store high-privilege plain-text tokens.',
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
        label: const Text('Need help finding your credentials?'),
        style: TextButton.styleFrom(
          foregroundColor: _SetupColors.onSurfaceVariant,
          textStyle: _SetupTextStyles.bodySmall,
        ),
      ),
    );
  }
}

final class _SetupTextStyles {
  const _SetupTextStyles._();

  static const title = TextStyle(
    color: _SetupColors.onSurface,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const label = TextStyle(
    color: _SetupColors.onSurface,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const button = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const captionStrong = TextStyle(
    color: _SetupColors.onSurface,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const caption = TextStyle(
    color: _SetupColors.onSurfaceVariant,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  static const bodySmall = TextStyle(
    color: _SetupColors.onSurfaceVariant,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const footnote = TextStyle(
    color: _SetupColors.onSurfaceVariant,
    fontSize: 11,
    height: 14 / 11,
    fontStyle: FontStyle.italic,
    letterSpacing: 0,
  );

  static const code = TextStyle(
    color: _SetupColors.onSurface,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );
}

final class _SetupColors {
  const _SetupColors._();

  static const primary = Color(0xFF000000);
  static const secondary = Color(0xFF0051D5);
  static const surface = Color(0xFFF7F9FB);
  static const surfaceBright = Color(0xFFF7F9FB);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFF2F4F6);
  static const surfaceContainer = Color(0xFFECEEF0);
  static const surfaceVariant = Color(0xFFE0E3E5);
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF45464D);
  static const outline = Color(0xFF76777D);
  static const outlineVariant = Color(0xFFC6C6CD);
  static const tertiaryFixedVariant = Color(0xFF38485D);
  static const warningForeground = Color(0xFFB45309);
}

OutlineInputBorder _outlineBorder(Color color, double radius) {
  return OutlineInputBorder(
    borderSide: BorderSide(color: color),
    borderRadius: BorderRadius.circular(radius),
  );
}
