import 'package:flutter/material.dart';

import '../../core/cloud/self_managed_setup_controller.dart';
import '../../core/cloud/self_managed_setup_models.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_button.dart';
import 'self_managed_setup_sections.dart';
import 'settings_ui.dart';

class SelfManagedSetupPage extends StatefulWidget {
  const SelfManagedSetupPage({
    super.key,
    this.controller,
  });

  final SelfManagedSetupController? controller;

  @override
  State<SelfManagedSetupPage> createState() => _SelfManagedSetupPageState();
}

class _SelfManagedSetupPageState extends State<SelfManagedSetupPage> {
  late final SelfManagedSetupController _controller;
  final _cloudflareAccountController = TextEditingController();
  final _providerController = TextEditingController(text: 'openai');
  final _apiKeyController = TextEditingController();
  final _embeddingApiKeyController = TextEditingController();
  final _multimodalApiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SelfManagedSetupController();
  }

  @override
  void dispose() {
    _cloudflareAccountController.dispose();
    _providerController.dispose();
    _apiKeyController.dispose();
    _embeddingApiKeyController.dispose();
    _multimodalApiKeyController.dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageShell(
      key: const ValueKey('self_managed_setup_root'),
      title: context.t.settings.selfManagedSetup.title,
      children: [
        Text(context.t.settings.selfManagedSetup.subtitle),
        const SizedBox(height: 16),
        SelfManagedSetupSections(
          controller: _controller,
          cloudflareAccountController: _cloudflareAccountController,
          providerController: _providerController,
          apiKeyController: _apiKeyController,
          embeddingApiKeyController: _embeddingApiKeyController,
          multimodalApiKeyController: _multimodalApiKeyController,
        ),
        const SizedBox(height: 16),
        SettingsActionBar(
          actions: [
            SettingsAction(
              key: const ValueKey('self_managed_authorize'),
              label: context.t.settings.selfManagedSetup.actions.authorize,
              onPressed: _controller.beginCloudflareAuthorization,
              variant: SlButtonVariant.outline,
            ),
            SettingsAction(
              key: const ValueKey('self_managed_deploy'),
              label: context.t.settings.selfManagedSetup.actions.deploy,
              onPressed: () {
                _controller.deploy(
                  SelfManagedSetupRequest(
                    cloudflareAccountLabel: _cloudflareAccountController.text,
                    provider: _providerController.text,
                    apiKey: _apiKeyController.text,
                    embeddingApiKey: _embeddingApiKeyController.text,
                    multimodalApiKey: _multimodalApiKeyController.text,
                  ),
                );
              },
            ),
            SettingsAction(
              key: const ValueKey('self_managed_retry'),
              label: context.t.settings.selfManagedSetup.actions.retry,
              onPressed: () {
                _controller.deploy(
                  SelfManagedSetupRequest(
                    cloudflareAccountLabel: _cloudflareAccountController.text,
                    provider: _providerController.text,
                    apiKey: _apiKeyController.text,
                    embeddingApiKey: _embeddingApiKeyController.text,
                    multimodalApiKey: _multimodalApiKeyController.text,
                  ),
                );
              },
              variant: SlButtonVariant.secondary,
            ),
            SettingsAction(
              key: const ValueKey('self_managed_reset'),
              label: context.t.settings.selfManagedSetup.actions.reset,
              onPressed: _controller.reset,
              variant: SlButtonVariant.outline,
            ),
          ],
        ),
      ],
    );
  }
}
