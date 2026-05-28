import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cloud/runtime_manifest.dart';
import '../../core/cloud/self_managed_setup_controller.dart';
import '../../core/cloud/self_managed_setup_models.dart';
import '../../i18n/strings.g.dart';

part 'self_managed_setup_sections_cards.dart';

class SelfManagedSetupSections extends StatelessWidget {
  const SelfManagedSetupSections({
    super.key,
    required this.controller,
    required this.cloudflareAccountController,
    required this.providerController,
    required this.apiKeyController,
    required this.embeddingApiKeyController,
    required this.multimodalApiKeyController,
    required this.isBusy,
    required this.isUninstallBusy,
    required this.onWriteSecrets,
    required this.onUninstallRuntime,
  });

  final SelfManagedSetupController controller;
  final TextEditingController cloudflareAccountController;
  final TextEditingController providerController;
  final TextEditingController apiKeyController;
  final TextEditingController embeddingApiKeyController;
  final TextEditingController multimodalApiKeyController;
  final bool isBusy;
  final bool isUninstallBusy;
  final VoidCallback onWriteSecrets;
  final Future<void> Function() onUninstallRuntime;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProgressRail(state: state),
            const SizedBox(height: 24),
            _ProviderSecretsCard(
              state: state,
              cloudflareAccountController: cloudflareAccountController,
              providerController: providerController,
              apiKeyController: apiKeyController,
              embeddingApiKeyController: embeddingApiKeyController,
              multimodalApiKeyController: multimodalApiKeyController,
              isBusy: isBusy,
              onWriteSecrets: onWriteSecrets,
            ),
            const SizedBox(height: 24),
            const _CloudflareAuthorizationCard(),
            const SizedBox(height: 24),
            _CapabilityVerificationCard(verification: state.verification),
            const SizedBox(height: 24),
            _RuntimeManifestCard(manifest: state.manifest),
            if (state.manifest != null ||
                state.isReady ||
                state.isUninstalled) ...[
              const SizedBox(height: 24),
              _RuntimeManagementCard(
                state: state,
                isBusy: isUninstallBusy,
                onUninstallRuntime: onUninstallRuntime,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ProgressRail extends StatelessWidget {
  const _ProgressRail({required this.state});

  final SelfManagedSetupState state;

  @override
  Widget build(BuildContext context) {
    final activeIndex = switch (state.step) {
      SelfManagedSetupStep.verifying || SelfManagedSetupStep.failed => 2,
      SelfManagedSetupStep.ready => 3,
      _ => 1,
    };
    final t = context.t.settings.selfManagedSetup.progress;
    final steps = [
      _SetupProgressStep(t.cloudflareAuthorized, completed: true),
      _SetupProgressStep(t.providerSecrets),
      _SetupProgressStep(t.capabilityChecks),
      _SetupProgressStep(t.runtimeManifest),
    ];
    return _SetupCard(
      padding: const EdgeInsets.all(16),
      backgroundColor: _SetupColors.surfaceLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              _ProgressStepView(
                step: steps[i],
                active: i == activeIndex,
                completed: steps[i].completed || i < activeIndex,
              ),
              if (i != steps.length - 1) const SizedBox(width: 32),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupProgressStep {
  const _SetupProgressStep(this.label, {this.completed = false});

  final String label;
  final bool completed;
}

class _ProgressStepView extends StatelessWidget {
  const _ProgressStepView({
    required this.step,
    required this.active,
    required this.completed,
  });

  final _SetupProgressStep step;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = active ? _SetupColors.secondary : _SetupColors.onSurface;
    final opacity = completed || active ? 1.0 : 0.42;
    return Opacity(
      opacity: opacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (completed)
            const Icon(
              Icons.check_circle_rounded,
              color: _SetupColors.secondary,
              size: 20,
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? _SetupColors.secondary : _SetupColors.outline,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            step.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderSecretsCard extends StatelessWidget {
  const _ProviderSecretsCard({
    required this.state,
    required this.cloudflareAccountController,
    required this.providerController,
    required this.apiKeyController,
    required this.embeddingApiKeyController,
    required this.multimodalApiKeyController,
    required this.isBusy,
    required this.onWriteSecrets,
  });

  final SelfManagedSetupState state;
  final TextEditingController cloudflareAccountController;
  final TextEditingController providerController;
  final TextEditingController apiKeyController;
  final TextEditingController embeddingApiKeyController;
  final TextEditingController multimodalApiKeyController;
  final bool isBusy;
  final VoidCallback onWriteSecrets;

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.selfManagedSetup;
    return _SetupCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: t.providerSecrets.title,
            subtitle: t.providerSecrets.subtitle,
          ),
          const SizedBox(height: 16),
          _ProviderSegmentedControl(controller: providerController),
          const SizedBox(height: 16),
          _SecretTextField(
            fieldKey: const ValueKey('self_managed_cloudflare_account'),
            controller: cloudflareAccountController,
            label: t.fields.cloudflareAccountLabel,
            obscure: false,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: providerController,
            builder: (context, value, _) {
              return _SecretTextField(
                fieldKey: const ValueKey('self_managed_api_key'),
                semanticsKey: const ValueKey(
                  'self_managed_api_key_semantics',
                ),
                pasteKey: const ValueKey('self_managed_api_key_paste'),
                controller: apiKeyController,
                label: _primaryKeyLabel(context, value.text),
              );
            },
          ),
          const SizedBox(height: 12),
          _SecretTextField(
            fieldKey: const ValueKey('self_managed_embedding_api_key'),
            semanticsKey: const ValueKey(
              'self_managed_embedding_api_key_semantics',
            ),
            pasteKey: const ValueKey(
              'self_managed_embedding_api_key_paste',
            ),
            controller: embeddingApiKeyController,
            label: t.fields.embeddingRuntimeSecret,
          ),
          const SizedBox(height: 12),
          _SecretTextField(
            fieldKey: const ValueKey('self_managed_multimodal_api_key'),
            semanticsKey: const ValueKey(
              'self_managed_multimodal_api_key_semantics',
            ),
            pasteKey: const ValueKey(
              'self_managed_multimodal_api_key_paste',
            ),
            controller: multimodalApiKeyController,
            label: t.fields.multimodalRuntimeSecret,
          ),
          const SizedBox(height: 8),
          _InlineNote(
            icon: Icons.info_outline_rounded,
            text: t.providerSecrets.storedAsSecret,
          ),
          if (state.hasError) ...[
            const SizedBox(height: 12),
            _InlineNote(
              icon: Icons.error_outline_rounded,
              text: state.errorCode ?? state.statusMessage,
              tone: _InlineNoteTone.warning,
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            key: const ValueKey('self_managed_write_secrets'),
            onPressed: isBusy ? null : onWriteSecrets,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              side: const BorderSide(color: _SetupColors.outline),
            ),
            child: Text(isBusy ? t.actions.writing : t.actions.writeSecrets),
          ),
        ],
      ),
    );
  }

  String _primaryKeyLabel(BuildContext context, String provider) {
    final t = context.t.settings.selfManagedSetup.fields;
    return switch (provider.trim().toLowerCase()) {
      'anthropic' => t.anthropicApiKey,
      'custom' => t.customProviderApiKey,
      _ => t.openAiApiKey,
    };
  }
}

class _ProviderSegmentedControl extends StatelessWidget {
  const _ProviderSegmentedControl({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final providers =
        context.t.settings.selfManagedSetup.providerSecrets.providers;
    final options = [
      _ProviderOption('openai', providers.openai),
      _ProviderOption('anthropic', providers.anthropic),
      _ProviderOption('custom', providers.custom),
    ];
    return ValueListenableBuilder<TextEditingValue>(
      key: const ValueKey('self_managed_provider'),
      valueListenable: controller,
      builder: (context, value, _) {
        final selected = value.text.trim().toLowerCase();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _SetupColors.surfaceContainer,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options)
                    _ProviderSegment(
                      option: option,
                      selected: option.value == selected,
                      onTap: () {
                        controller.value = TextEditingValue(
                          text: option.value,
                          selection: TextSelection.collapsed(
                            offset: option.value.length,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProviderOption {
  const _ProviderOption(this.value, this.label);

  final String value;
  final String label;
}

class _ProviderSegment extends StatelessWidget {
  const _ProviderSegment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ProviderOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selected ? null : onTap,
      borderRadius: BorderRadius.circular(2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _SetupColors.surfaceLowest : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          option.label,
          style: TextStyle(
            color:
                selected ? _SetupColors.primary : _SetupColors.onSurfaceVariant,
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _SecretTextField extends StatelessWidget {
  const _SecretTextField({
    this.fieldKey,
    this.semanticsKey,
    this.pasteKey,
    required this.controller,
    required this.label,
    this.obscure = true,
  });

  final Key? fieldKey;
  final Key? semanticsKey;
  final Key? pasteKey;
  final TextEditingController controller;
  final String label;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: _SetupColors.onSurfaceVariant,
            fontSize: 11,
            height: 14 / 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          key: semanticsKey,
          label: label,
          textField: true,
          obscured: obscure,
          value: obscure ? _obscuredSemanticsValue(context) : controller.text,
          onSetText: _replaceText,
          onPaste: obscure ? _pasteFromClipboard : null,
          child: TextField(
            key: fieldKey,
            controller: controller,
            obscureText: obscure,
            enableSuggestions: !obscure,
            autocorrect: false,
            maxLines: 1,
            style: const TextStyle(
              color: _SetupColors.onSurface,
              fontSize: 13,
              height: 18 / 13,
              letterSpacing: 0,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: _SetupColors.surfaceLow,
              isDense: true,
              suffixIcon: obscure
                  ? _SecretFieldSuffix(
                      pasteKey: pasteKey,
                      onPaste: _pasteFromClipboard,
                    )
                  : null,
              suffixIconConstraints: obscure
                  ? const BoxConstraints(minHeight: 40, minWidth: 76)
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: _outlineBorder(_SetupColors.outlineVariant),
              focusedBorder: _outlineBorder(_SetupColors.secondary),
              border: _outlineBorder(_SetupColors.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }

  String _obscuredSemanticsValue(BuildContext context) {
    if (controller.text.isEmpty) return '';
    return context
        .t.settings.selfManagedSetup.providerSecrets.secretValueEntered;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _replaceText(text);
  }

  void _replaceText(String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _SecretFieldSuffix extends StatelessWidget {
  const _SecretFieldSuffix({
    required this.pasteKey,
    required this.onPaste,
  });

  final Key? pasteKey;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.selfManagedSetup;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: pasteKey,
          tooltip: t.actions.pasteSecret,
          onPressed: onPaste,
          icon: const Icon(
            Icons.content_paste_rounded,
            size: 18,
            color: _SetupColors.onSurfaceVariant,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          visualDensity: VisualDensity.compact,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Tooltip(
            message: t.providerSecrets.secretValueHidden,
            child: const Icon(
              Icons.visibility_off_outlined,
              size: 20,
              color: _SetupColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
