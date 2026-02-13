part of 'chat_page.dart';

extension _ChatPageStateAttachmentAnnotationUiState on _ChatPageState {
  Future<({bool enabled, bool canRunNow})> _loadAttachmentAnnotationUiState(
    NativeAppBackend backend,
    Uint8List sessionKey,
  ) async {
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);

    MediaAnnotationConfig? config;
    try {
      config = await const RustMediaAnnotationConfigStore().read(sessionKey);
    } catch (_) {
      config = null;
    }
    if (config == null || !config.annotateEnabled) {
      return (enabled: false, canRunNow: false);
    }

    if (!mounted) {
      return (enabled: false, canRunNow: false);
    }

    ContentEnrichmentConfig? contentConfig;
    try {
      contentConfig = await const RustContentEnrichmentConfigStore()
          .readContentEnrichment(sessionKey);
    } catch (_) {
      contentConfig = null;
    }

    final gatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

    final hasGateway = gatewayConfig.baseUrl.trim().isNotEmpty;
    String? idToken;
    if (subscriptionStatus == SubscriptionStatus.entitled) {
      try {
        idToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        idToken = null;
      }
    }
    final hasIdToken = (idToken?.trim() ?? '').isNotEmpty;

    List<LlmProfile> llmProfiles = const <LlmProfile>[];
    try {
      llmProfiles = await backend.listLlmProfiles(sessionKey);
    } catch (_) {
      llmProfiles = const <LlmProfile>[];
    }

    LlmProfile? findProfile(String id) {
      for (final p in llmProfiles) {
        if (p.id == id) return p;
      }
      return null;
    }

    LlmProfile? activeProfile() {
      for (final p in llmProfiles) {
        if (p.isActive) return p;
      }
      return null;
    }

    bool canUseOpenAiProfile(LlmProfile? profile) {
      return profile != null && profile.providerType == 'openai-compatible';
    }

    final canUseCloud = subscriptionStatus == SubscriptionStatus.entitled &&
        hasGateway &&
        hasIdToken;
    final allowRuntimeOcrFallback =
        subscriptionStatus != SubscriptionStatus.entitled &&
            (contentConfig?.ocrEnabled ?? true);

    final desiredMode = config.providerMode.trim();
    if (desiredMode == 'cloud_gateway') {
      final canRun = canUseCloud || allowRuntimeOcrFallback;
      return (enabled: true, canRunNow: canRun);
    }

    if (desiredMode == 'byok_profile') {
      final id = config.byokProfileId?.trim();
      final profile = id == null || id.isEmpty ? null : findProfile(id);
      final canRun = canUseOpenAiProfile(profile) || allowRuntimeOcrFallback;
      return (enabled: true, canRunNow: canRun);
    }

    if (canUseCloud || allowRuntimeOcrFallback) {
      return (enabled: true, canRunNow: true);
    }

    final canRun = canUseOpenAiProfile(activeProfile());
    return (enabled: true, canRunNow: canRun);
  }
}

Widget _buildComposerInlineButton(
  BuildContext context, {
  required Key key,
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
  required Color backgroundColor,
  required Color foregroundColor,
  Color? borderColor,
}) {
  final textTheme = Theme.of(context).textTheme;
  final isEnabled = onPressed != null;

  final effectiveBackground =
      isEnabled ? backgroundColor : backgroundColor.withOpacity(0.52);
  final effectiveForeground =
      isEnabled ? foregroundColor : foregroundColor.withOpacity(0.62);

  final borderRadius = BorderRadius.circular(999);
  final borderSide =
      borderColor == null ? BorderSide.none : BorderSide(color: borderColor);

  return Semantics(
    key: key,
    button: true,
    label: label,
    child: Material(
      color: effectiveBackground,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: borderSide,
      ),
      child: InkWell(
        onTap: onPressed,
        canRequestFocus: false,
        borderRadius: borderRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: effectiveForeground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: textTheme.labelLarge?.copyWith(
                    color: effectiveForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

extension _ChatPageStateComposerUi on _ChatPageState {
  Widget _buildCompactAttachButton(
    BuildContext context, {
    bool includeLeadingPadding = true,
  }) {
    if (!_supportsImageUpload && !_supportsAudioRecording) {
      return const SizedBox.shrink();
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_supportsDesktopRecordAudioAction) ...[
          SlIconButton(
            key: const ValueKey('chat_record_audio'),
            icon: Icons.mic_rounded,
            size: 44,
            iconSize: 22,
            tooltip: context.t.chat.attachRecordAudio,
            onPressed: _isComposerBusy
                ? null
                : () => unawaited(_recordAndSendAudioFromSheet()),
          ),
          const SizedBox(width: 8),
        ],
        SlIconButton(
          key: const ValueKey('chat_attach'),
          icon: Icons.add_rounded,
          size: 44,
          iconSize: 22,
          tooltip: context.t.chat.attachTooltip,
          onPressed: _isComposerBusy ? null : _openAttachmentSheet,
        ),
      ],
    );

    if (!includeLeadingPadding) return row;

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: row,
    );
  }

  Widget _buildComposerMarkdownEditorButton(
    BuildContext context, {
    required ColorScheme colorScheme,
    required SlTokens tokens,
  }) {
    return _buildComposerInlineButton(
      context,
      key: const ValueKey('chat_open_markdown_editor'),
      label: context.t.chat.markdownEditor.openButton,
      icon: Icons.open_in_full_rounded,
      onPressed: _isComposerBusy ? null : _openMarkdownEditor,
      backgroundColor: colorScheme.tertiaryContainer,
      foregroundColor: colorScheme.onTertiaryContainer,
      borderColor: tokens.borderSubtle,
    );
  }

  Widget _buildDesktopMarkdownEditorButton(BuildContext context) {
    return SlButton(
      buttonKey: const ValueKey('chat_open_markdown_editor'),
      icon: const Icon(Icons.open_in_full_rounded, size: 18),
      variant: SlButtonVariant.outline,
      onPressed: _isComposerBusy ? null : _openMarkdownEditor,
      child: Text(context.t.chat.markdownEditor.openButton),
    );
  }

  Widget _buildCompactComposerActions(
    BuildContext context, {
    required SlTokens tokens,
    required ColorScheme colorScheme,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, child) {
        final hasText = value.text.trim().isNotEmpty;
        final hasAttachActions =
            _supportsImageUpload || _supportsAudioRecording;

        if (_asking) {
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _buildComposerInlineButton(
              context,
              key: const ValueKey('chat_stop'),
              label: _stopRequested
                  ? context.t.common.actions.stopping
                  : context.t.common.actions.stop,
              icon: Icons.stop_circle_outlined,
              onPressed: _stopRequested ? null : _stopAsk,
              backgroundColor: Colors.transparent,
              foregroundColor: colorScheme.onSurface,
              borderColor: tokens.borderSubtle,
            ),
          );
        }

        if (!hasText) {
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildComposerMarkdownEditorButton(
                  context,
                  colorScheme: colorScheme,
                  tokens: tokens,
                ),
                if (hasAttachActions) ...[
                  const SizedBox(width: 8),
                  _buildCompactAttachButton(
                    context,
                    includeLeadingPadding: false,
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildComposerMarkdownEditorButton(
                context,
                colorScheme: colorScheme,
                tokens: tokens,
              ),
              const SizedBox(width: 8),
              if (_showConfigureAiEntry) ...[
                _buildComposerInlineButton(
                  context,
                  key: const ValueKey('chat_configure_ai'),
                  label: context.t.common.actions.configureAi,
                  icon: Icons.settings_suggest_rounded,
                  onPressed:
                      _isComposerBusy ? null : _openAskAiSettingsFromComposer,
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
              ] else if (_canAskAiNow) ...[
                _buildComposerInlineButton(
                  context,
                  key: const ValueKey('chat_ask_ai'),
                  label: context.t.common.actions.askAi,
                  icon: Icons.auto_awesome_rounded,
                  onPressed: _isComposerBusy ? null : _askAi,
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
              ],
              _buildComposerInlineButton(
                context,
                key: const ValueKey('chat_send'),
                label: context.t.common.actions.send,
                icon: Icons.send_rounded,
                onPressed: _isComposerBusy ? null : _send,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
            ],
          ),
        );
      },
    );
  }
}
