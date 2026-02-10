part of 'chat_page.dart';

extension _ChatPageStateAttachmentAnnotationUiState on _ChatPageState {
  Future<({bool enabled, bool canRunNow})> _loadAttachmentAnnotationUiState(
    NativeAppBackend backend,
    Uint8List sessionKey,
  ) async {
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

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
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

    final desiredMode = config.providerMode.trim();
    if (desiredMode == 'cloud_gateway') {
      final canRun = subscriptionStatus == SubscriptionStatus.entitled &&
          hasGateway &&
          hasIdToken;
      return (enabled: true, canRunNow: canRun);
    }

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

    final canUseCloud = subscriptionStatus == SubscriptionStatus.entitled &&
        hasGateway &&
        hasIdToken;

    if (desiredMode == 'byok_profile') {
      final id = config.byokProfileId?.trim();
      final profile = id == null || id.isEmpty ? null : findProfile(id);
      final canRun =
          profile != null && profile.providerType == 'openai-compatible';
      return (enabled: true, canRunNow: canRun);
    }

    if (canUseCloud) {
      return (enabled: true, canRunNow: true);
    }

    final active = activeProfile();
    final canRun = active != null && active.providerType == 'openai-compatible';
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

extension _ChatPageStateVoiceComposerUi on _ChatPageState {
  Widget _buildVoiceModeToggleButton(BuildContext context) {
    if (!_supportsPressToTalk) return const SizedBox.shrink();

    final isVoiceMode = _voiceInputMode;
    final icon = isVoiceMode ? Icons.keyboard_rounded : Icons.mic_none_rounded;
    final tooltip = isVoiceMode
        ? context.t.chat.switchToKeyboardInput
        : context.t.chat.switchToVoiceInput;

    return SlIconButton(
      key: const ValueKey('chat_toggle_voice_input'),
      icon: icon,
      size: 44,
      iconSize: 22,
      tooltip: tooltip,
      onPressed: _isComposerBusy ? null : _toggleVoiceInputMode,
    );
  }

  Widget _buildPressToTalkButton(
    BuildContext context, {
    required SlTokens tokens,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = _pressToTalkActive;

    final backgroundColor =
        isActive ? colorScheme.primary.withOpacity(0.16) : tokens.surface;
    final borderColor = isActive ? colorScheme.primary : tokens.borderSubtle;
    final textColor = isActive ? colorScheme.primary : colorScheme.onSurface;
    final label =
        isActive ? context.t.chat.releaseToConvert : context.t.chat.holdToTalk;

    return Semantics(
      key: const ValueKey('chat_press_to_talk'),
      button: true,
      label: label,
      child: Listener(
        onPointerDown: _onPressToTalkPointerDown,
        onPointerUp: _onPressToTalkPointerUp,
        onPointerCancel: _onPressToTalkPointerCancel,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPressToTalkCenterOverlay(
    BuildContext context, {
    required SlTokens tokens,
  }) {
    if (!_pressToTalkActive && !_pressToTalkRecognizing) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isRecording = _pressToTalkActive;
    final title = isRecording
        ? context.t.chat.recordingInProgress
        : _pressToTalkRecognizingTitle();
    final subtitle = isRecording
        ? context.t.chat.releaseToConvert
        : _pressToTalkRecognizingHint();

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Container(
              key: ValueKey<String>(
                isRecording
                    ? 'chat_press_to_talk_overlay_recording'
                    : 'chat_press_to_talk_overlay_recognizing',
              ),
              constraints: const BoxConstraints(maxWidth: 280),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: tokens.surface.withOpacity(0.96),
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                border: Border.all(color: tokens.borderSubtle),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.16),
                    blurRadius: 20,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isRecording
                                ? colorScheme.primary
                                : colorScheme.secondary,
                          ),
                        ),
                        Icon(
                          isRecording
                              ? Icons.mic_rounded
                              : Icons.graphic_eq_rounded,
                          color: isRecording
                              ? colorScheme.primary
                              : colorScheme.secondary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
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

  Widget _buildCompactAttachButton(BuildContext context) {
    if (!_supportsImageUpload && !_supportsAudioRecording) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
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
      ),
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

        if (_voiceInputMode && _supportsPressToTalk) {
          return _buildCompactAttachButton(context);
        }

        if (!hasText) {
          return _buildCompactAttachButton(context);
        }

        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
