import 'package:flutter/material.dart';

import '../../core/cloud/self_managed_setup_controller.dart';
import '../../core/cloud/self_managed_setup_models.dart';
import '../../i18n/strings.g.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'settings_ui.dart';

class SelfManagedSetupSections extends StatelessWidget {
  const SelfManagedSetupSections({
    super.key,
    required this.controller,
    required this.cloudflareAccountController,
    required this.providerController,
    required this.apiKeyController,
    required this.embeddingApiKeyController,
    required this.multimodalApiKeyController,
  });

  final SelfManagedSetupController controller;
  final TextEditingController cloudflareAccountController;
  final TextEditingController providerController;
  final TextEditingController apiKeyController;
  final TextEditingController embeddingApiKeyController;
  final TextEditingController multimodalApiKeyController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final refreshedState = controller.state;
        return SettingsSection(
          children: [
            Padding(
              padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const ValueKey('self_managed_cloudflare_account'),
                    controller: cloudflareAccountController,
                    decoration: InputDecoration(
                      labelText: context
                          .t.settings.selfManagedSetup.fields.accountLabel,
                    ),
                  ),
                  const SizedBox(height: AgentDesignTokens.gapMd),
                  TextField(
                    key: const ValueKey('self_managed_provider'),
                    controller: providerController,
                    decoration: InputDecoration(
                      labelText: context
                          .t.settings.selfManagedSetup.fields.providerLabel,
                    ),
                  ),
                  const SizedBox(height: AgentDesignTokens.gapMd),
                  TextField(
                    key: const ValueKey('self_managed_api_key'),
                    controller: apiKeyController,
                    decoration: InputDecoration(
                      labelText: context
                          .t.settings.selfManagedSetup.fields.apiKeyLabel,
                    ),
                  ),
                  const SizedBox(height: AgentDesignTokens.gapMd),
                  TextField(
                    key: const ValueKey('self_managed_embedding_api_key'),
                    controller: embeddingApiKeyController,
                    decoration: InputDecoration(
                      labelText: context.t.settings.selfManagedSetup.fields
                          .embeddingApiKeyLabel,
                    ),
                  ),
                  const SizedBox(height: AgentDesignTokens.gapMd),
                  TextField(
                    key: const ValueKey('self_managed_multimodal_api_key'),
                    controller: multimodalApiKeyController,
                    decoration: InputDecoration(
                      labelText: context.t.settings.selfManagedSetup.fields
                          .multimodalApiKeyLabel,
                    ),
                  ),
                  const SizedBox(height: AgentDesignTokens.gapLg),
                  Text(_statusLabel(context, refreshedState)),
                  if (refreshedState.errorCode != null) ...[
                    const SizedBox(height: AgentDesignTokens.gapSm),
                    SettingsInlineMessage(
                      message: refreshedState.errorCode!,
                      tone: SettingsInlineMessageTone.error,
                    ),
                  ],
                  if (refreshedState.manifest != null) ...[
                    const SizedBox(height: AgentDesignTokens.gapSm),
                    Text(refreshedState.manifest!.apiBaseUrl),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _statusLabel(BuildContext context, SelfManagedSetupState state) {
    switch (state.step) {
      case SelfManagedSetupStep.idle:
        return context.t.settings.selfManagedSetup.status.idle;
      case SelfManagedSetupStep.authorizing:
        return context.t.settings.selfManagedSetup.status.authorizing;
      case SelfManagedSetupStep.deploying:
        return context.t.settings.selfManagedSetup.status.deploying;
      case SelfManagedSetupStep.verifying:
        return 'Verifying model capabilities...';
      case SelfManagedSetupStep.ready:
        return context.t.settings.selfManagedSetup.status.ready;
      case SelfManagedSetupStep.failed:
        return context.t.settings.selfManagedSetup.status.failed;
    }
  }
}
