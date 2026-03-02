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
  VoidCallback? onLongPress,
  required Color backgroundColor,
  required Color foregroundColor,
  Color? borderColor,
  bool iconOnly = false,
  double minButtonWidth = 44,
}) {
  return ChatComposerInlineButton(
    buttonKey: key,
    label: label,
    icon: icon,
    onPressed: onPressed,
    onLongPress: onLongPress,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    borderColor: borderColor,
    iconOnly: iconOnly,
    minButtonWidth: minButtonWidth,
  );
}

extension _ChatPageStateComposerUi on _ChatPageState {
  Widget _buildAttachmentSendFeedbackBanner(BuildContext context) {
    return AttachmentSendFeedbackBanner(
      key: const ValueKey('chat_attachment_send_feedback'),
      text: context.t.sync.progressDialog.uploadingMedia,
    );
  }

  IconData _composerDraftAttachmentIcon(String mimeType) {
    final normalized = mimeType.trim().toLowerCase();
    if (normalized.startsWith('image/')) {
      return Icons.image_rounded;
    }
    if (normalized.startsWith('audio/')) {
      return Icons.audiotrack_rounded;
    }
    if (normalized.startsWith('video/')) {
      return Icons.movie_rounded;
    }
    if (normalized == 'application/pdf') {
      return Icons.picture_as_pdf_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Widget _buildComposerDraftAttachmentStrip(
    BuildContext context, {
    required SlTokens tokens,
  }) {
    if (_composerDraftAttachments.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final failedCount = _composerDraftAttachments
        .where((draft) => _failedComposerDraftLocalIds.contains(draft.localId))
        .length;
    return Container(
      key: const ValueKey('chat_draft_attachment_list'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failedCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChatAttachmentSendFailureChip(
                key: const ValueKey('chat_attachment_failed_retry_banner'),
                failedCount: failedCount,
                onRetry: _isComposerBusy ? null : () => unawaited(_send()),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _composerDraftAttachments
                .map(
                  (draft) => InputChip(
                    key: ValueKey('chat_draft_attachment_${draft.localId}'),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      _failedComposerDraftLocalIds.contains(draft.localId)
                          ? Icons.error_outline_rounded
                          : _composerDraftAttachmentIcon(
                              draft.normalizedMimeType),
                      size: 16,
                      color:
                          _failedComposerDraftLocalIds.contains(draft.localId)
                              ? colorScheme.error
                              : null,
                    ),
                    backgroundColor:
                        _failedComposerDraftLocalIds.contains(draft.localId)
                            ? colorScheme.errorContainer.withOpacity(0.28)
                            : null,
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        draft.normalizedFilename,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onDeleted: _isComposerBusy
                        ? null
                        : () => _removeComposerAttachmentDraft(draft.localId),
                    deleteIcon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
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
                : () => unawaited(_recordAndAttachAudioFromSheet()),
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
    double size = 40,
    double iconSize = 20,
  }) {
    return Semantics(
      button: true,
      label: context.t.chat.markdownEditor.openButton,
      child: SlIconButton(
        key: const ValueKey('chat_open_markdown_editor'),
        icon: Icons.open_in_full_rounded,
        size: size,
        iconSize: iconSize,
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
    required double maxComposerWidth,
  }) {
    return ListenableBuilder(
      listenable: _inputFocusNode,
      builder: (context, child) {
        final showMarkdownButton = _inputFocusNode.hasFocus;

        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, child) {
            final hasText = value.text.trim().isNotEmpty;
            final hasDraftAttachments = _composerDraftAttachments.isNotEmpty;
            final hasAttachActions =
                _supportsImageUpload || _supportsAudioRecording;
            final prioritizeInputWidth =
                showMarkdownButton && hasText && maxComposerWidth <= 340;
            final canAskAiFromComposer = _showConfigureAiEntry || _canAskAiNow;
            final showAiAction =
                hasText && canAskAiFromComposer && !prioritizeInputWidth;
            final collapseAiActionIntoSend =
                hasText && canAskAiFromComposer && prioritizeInputWidth;
            final sendLongPressAction = collapseAiActionIntoSend
                ? (_showConfigureAiEntry
                    ? (_isComposerBusy ? null : _openAskAiSettingsFromComposer)
                    : (_canAskAiNow ? (_isComposerBusy ? null : _askAi) : null))
                : null;

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

            if (!hasText && !hasDraftAttachments) {
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
                  if (showMarkdownButton) ...[
                    _buildComposerMarkdownEditorButton(context),
                    const SizedBox(width: 8),
                  ],
                  if (!hasText && hasAttachActions) ...[
                    _buildCompactAttachButton(
                      context,
                      includeLeadingPadding: false,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (showAiAction && _showConfigureAiEntry) ...[
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
                  ] else if (showAiAction && _canAskAiNow) ...[
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
                    onLongPress: sendLongPressAction,
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
