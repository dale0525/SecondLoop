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
  bool iconOnly = false,
  double minButtonWidth = 44,
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
          constraints: BoxConstraints(
            minHeight: 44,
            minWidth: minButtonWidth,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 10 : 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: effectiveForeground),
                if (!iconOnly) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: textTheme.labelLarge?.copyWith(
                      color: effectiveForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

extension _ChatPageStateComposerUi on _ChatPageState {
  Widget _buildAttachmentSendFeedbackBanner(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      label: context.t.sync.progressDialog.uploadingMedia,
      child: SlSurface(
        key: const ValueKey('chat_attachment_send_feedback'),
        color: colorScheme.secondaryContainer.withOpacity(0.42),
        borderColor: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.1,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.t.sync.progressDialog.uploadingMedia,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildComposerMarkdownEditorButton(BuildContext context) {
    return Semantics(
      button: true,
      label: context.t.chat.markdownEditor.openButton,
      child: SlIconButton(
        key: const ValueKey('chat_open_markdown_editor'),
        icon: Icons.open_in_full_rounded,
        size: 40,
        iconSize: 20,
        tooltip: context.t.chat.markdownEditor.openButton,
        canRequestFocus: false,
        triggerOnTapDown: true,
        onPressed: _isComposerBusy ? null : _openMarkdownEditor,
      ),
    );
  }

  Widget _buildDesktopMarkdownEditorButton(BuildContext context) {
    return _buildComposerMarkdownEditorButton(context);
  }

  Widget _buildCompactComposerActions(
    BuildContext context, {
    required SlTokens tokens,
    required ColorScheme colorScheme,
  }) {
    return ListenableBuilder(
      listenable: _inputFocusNode,
      builder: (context, child) {
        final showMarkdownButton = _inputFocusNode.hasFocus;

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
                  iconOnly: true,
                ),
              );
            }

            if (!hasText) {
              if (!hasAttachActions) {
                if (!showMarkdownButton) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildComposerMarkdownEditorButton(context),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showMarkdownButton) ...[
                      _buildComposerMarkdownEditorButton(context),
                      const SizedBox(width: 8),
                    ],
                    if (hasAttachActions)
                      _buildCompactAttachButton(
                        context,
                        includeLeadingPadding: false,
                      ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showConfigureAiEntry) ...[
                    _buildComposerInlineButton(
                      context,
                      key: const ValueKey('chat_configure_ai'),
                      label: context.t.common.actions.configureAi,
                      icon: Icons.settings_suggest_rounded,
                      onPressed: _isComposerBusy
                          ? null
                          : _openAskAiSettingsFromComposer,
                      backgroundColor: colorScheme.secondaryContainer,
                      foregroundColor: colorScheme.onSecondaryContainer,
                      iconOnly: true,
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
                      iconOnly: true,
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
                    iconOnly: true,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
