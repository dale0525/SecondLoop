import 'package:flutter/material.dart';

import '../../core/cloud/self_managed_setup_controller.dart';
import '../../core/cloud/self_managed_setup_models.dart';
import '../../core/cloud/runtime_connection_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_tokens.dart';
import 'self_managed_setup_sections.dart';

part 'self_managed_setup_cloudflare_oauth_button.dart';
part 'self_managed_setup_cloudflare_connection_card.dart';

class SelfManagedSetupPage extends StatefulWidget {
  const SelfManagedSetupPage({
    super.key,
    this.controller,
    this.initialConnection,
    this.initialCloudflareAccountLabel = 'personal-vault',
  });

  final SelfManagedSetupController? controller;
  final CloudRuntimeConnection? initialConnection;
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
  var _uninstallBusy = false;
  var _manualExpanded = false;
  var _showSetupDetails = false;
  var _oauthAuthorized = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SelfManagedSetupController();
    _cloudflareAccountController = TextEditingController(
      text: widget.initialCloudflareAccountLabel,
    );
    final initialConnection = widget.initialConnection;
    if (initialConnection != null) {
      _controller.restoreConnection(initialConnection);
      _showSetupDetails = true;
    }
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

  Future<void> _startCloudflareOAuth() async {
    if (_busy || _uninstallBusy) return;
    setState(() {
      _busy = true;
      _showSetupDetails = false;
    });
    try {
      final result = await _controller.authorizeCloudflareOAuth(
        accountLabel: _cloudflareAccountController.text.trim(),
      );
      if (!mounted || result == null) return;
      _cloudflareAccountController.text = result.cloudflareAccountId;
      _cloudflareAccountIdController.text = result.cloudflareAccountId;
      _cloudflareApiTokenController.clear();
      _manualExpanded = false;
      _oauthAuthorized = true;
      setState(() => _showSetupDetails = true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _verifyCloudflareConnection() {
    if (!_manualExpanded) {
      if (!_controller.state.isCloudflareReady) {
        _startCloudflareOAuth();
      }
      setState(() => _showSetupDetails = true);
      return;
    }
    final ok = _controller.prepareManualCloudflareAuthorization(
      accountId: _cloudflareAccountIdController.text,
      apiToken: _cloudflareApiTokenController.text,
    );
    if (!ok) return;
    _cloudflareAccountController.text =
        _cloudflareAccountIdController.text.trim();
    _oauthAuthorized = false;
    setState(() => _showSetupDetails = true);
  }

  Future<void> _runSetup() async {
    if (_busy || _uninstallBusy) return;
    setState(() => _busy = true);
    try {
      final usesManualCloudflareCredentials = !_oauthAuthorized &&
          (_cloudflareAccountIdController.text.trim().isNotEmpty ||
              _cloudflareApiTokenController.text.trim().isNotEmpty);
      await _controller.deploy(
        SelfManagedSetupRequest(
          cloudflareAccountLabel: _cloudflareAccountController.text.trim(),
          provider: _providerController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
          embeddingApiKey: _embeddingApiKeyController.text.trim(),
          multimodalApiKey: _multimodalApiKeyController.text.trim(),
          cloudflareAuthorizationMethod: usesManualCloudflareCredentials
              ? SelfManagedCloudflareAuthorizationMethod.manual
              : SelfManagedCloudflareAuthorizationMethod.oauth,
          cloudflareAccountId: usesManualCloudflareCredentials
              ? _cloudflareAccountIdController.text.trim()
              : '',
          cloudflareApiToken: usesManualCloudflareCredentials
              ? _cloudflareApiTokenController.text.trim()
              : '',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runUninstall() async {
    if (_busy || _uninstallBusy) return;
    setState(() => _uninstallBusy = true);
    try {
      final usesManualCloudflareCredentials = !_oauthAuthorized;
      await _controller.uninstall(
        SelfManagedRuntimeUninstallRequest(
          cloudflareAccountLabel: _cloudflareAccountController.text.trim(),
          cloudflareAuthorizationMethod: usesManualCloudflareCredentials
              ? SelfManagedCloudflareAuthorizationMethod.manual
              : SelfManagedCloudflareAuthorizationMethod.oauth,
          cloudflareAccountId: usesManualCloudflareCredentials
              ? _cloudflareAccountIdController.text.trim()
              : '',
          cloudflareApiToken: usesManualCloudflareCredentials
              ? _cloudflareApiTokenController.text.trim()
              : '',
        ),
      );
      if (_controller.state.isUninstalled) {
        _cloudflareApiTokenController.clear();
        _oauthAuthorized = false;
      }
    } finally {
      if (mounted) {
        setState(() => _uninstallBusy = false);
      }
    }
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
                                  isUninstallBusy: _uninstallBusy,
                                  onWriteSecrets: _runSetup,
                                  onUninstallRuntime: _runUninstall,
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
