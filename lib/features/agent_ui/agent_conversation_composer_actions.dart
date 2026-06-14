part of 'agent_conversation_page.dart';

final class _ComposerActionButtons extends StatelessWidget {
  const _ComposerActionButtons({
    required this.busy,
    required this.recordingAudio,
    required this.focusNode,
    required this.supportsAudioRecording,
    required this.onAttach,
    required this.onOpenMarkdownEditor,
    required this.onRecordAudio,
    this.foregroundColor,
    this.disabledForegroundColor,
  });

  final bool busy;
  final bool recordingAudio;
  final FocusNode focusNode;
  final bool supportsAudioRecording;
  final VoidCallback onAttach;
  final VoidCallback onOpenMarkdownEditor;
  final VoidCallback onRecordAudio;
  final Color? foregroundColor;
  final Color? disabledForegroundColor;

  @override
  Widget build(BuildContext context) {
    final chatT = context.t.chat;
    final colors = context.agentOs;
    final style = IconButton.styleFrom(
      foregroundColor: foregroundColor,
      disabledForegroundColor: disabledForegroundColor,
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      hoverColor: colors.surfaceContainerHigh,
      fixedSize: const Size.square(32),
      minimumSize: const Size.square(32),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
      ),
    );
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        return DecoratedBox(
          key: const ValueKey('chat_composer_actions'),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('chat_attach'),
                  tooltip: context.t.chat.operating.desktopWorkbench.attach,
                  onPressed: busy ? null : onAttach,
                  style: style,
                  iconSize: 18,
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                if (focusNode.hasFocus)
                  IconButton(
                    key: const ValueKey('chat_markdown_editor_open'),
                    tooltip: chatT.markdownEditor.openButton,
                    onPressed: busy ? null : onOpenMarkdownEditor,
                    style: style,
                    iconSize: 18,
                    icon: const Icon(Icons.notes_rounded),
                  ),
                if (supportsAudioRecording && !recordingAudio)
                  IconButton(
                    key: const ValueKey('chat_record_audio'),
                    tooltip: chatT.attachRecordAudio,
                    onPressed: busy ? null : onRecordAudio,
                    style: style,
                    iconSize: 18,
                    icon: const Icon(Icons.mic_none_rounded),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class _ComposerResponsiveControls extends StatelessWidget {
  const _ComposerResponsiveControls({
    required this.actions,
    required this.input,
    required this.send,
    required this.recordingAudio,
    required this.onStopRecording,
    required this.onCancelRecording,
    this.compactBreakpoint = 520,
  });

  final Widget actions;
  final Widget input;
  final Widget send;
  final bool recordingAudio;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recordingAudio) ...[
          _ComposerRecordingStatusStrip(
            onStop: onStopRecording,
            onCancel: onCancelRecording,
          ),
          const SizedBox(height: 8),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < compactBreakpoint;
            if (compact) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  input,
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      actions,
                      const Spacer(),
                      send,
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                actions,
                const SizedBox(width: 8),
                Expanded(child: input),
                const SizedBox(width: 8),
                send,
              ],
            );
          },
        ),
      ],
    );
  }
}

final class _ComposerTextInputShell extends StatelessWidget {
  const _ComposerTextInputShell({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: ColoredBox(
        color: colors.surface,
        child: child,
      ),
    );
  }
}

InputDecoration _composerTextInputDecoration({
  required String hintText,
  TextStyle? hintStyle,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: hintStyle,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 12,
    ),
  );
}

final class _ComposerRecordingStatusStrip extends StatelessWidget {
  const _ComposerRecordingStatusStrip({
    required this.onStop,
    required this.onCancel,
  });

  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    final chatT = context.t.chat;
    final actionsT = context.t.common.actions;
    final errorColor = Theme.of(context).colorScheme.error;
    return DecoratedBox(
      key: const ValueKey('chat_recording_status'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        child: Row(
          children: [
            Icon(Icons.mic_rounded, size: 18, color: errorColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chatT.recordingInProgress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.labelLg.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              key: const ValueKey('chat_recording_cancel'),
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text(actionsT.cancel),
              style: TextButton.styleFrom(
                minimumSize: const Size(36, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              key: const ValueKey('chat_recording_stop'),
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: Text(actionsT.stop),
              style: FilledButton.styleFrom(
                minimumSize: const Size(36, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onSecondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AgentOperatingSystemTokens.radiusMd,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingComposerSendButton extends StatelessWidget {
  const _OperatingComposerSendButton({
    required this.controller,
    required this.busy,
    required this.hasAttachments,
    required this.onSend,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.disabledBackgroundColor,
    required this.disabledForegroundColor,
    required this.icon,
    required this.size,
    required this.radius,
  });

  final TextEditingController controller;
  final bool busy;
  final bool hasAttachments;
  final VoidCallback onSend;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color disabledBackgroundColor;
  final Color disabledForegroundColor;
  final IconData icon;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (value.text.trim().isEmpty && !hasAttachments) {
          return const SizedBox.shrink();
        }
        final enabled =
            !busy && (value.text.trim().isNotEmpty || hasAttachments);
        return SizedBox.square(
          dimension: size,
          child: FilledButton(
            key: const ValueKey('chat_send'),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              disabledBackgroundColor: disabledBackgroundColor,
              disabledForegroundColor: disabledForegroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
            onPressed: enabled ? onSend : null,
            child: Icon(icon, size: 20),
          ),
        );
      },
    );
  }
}

final class _OperatingFollowUpComposerInputRow extends StatelessWidget {
  const _OperatingFollowUpComposerInputRow({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.recordingAudio,
    required this.placeholder,
    required this.supportsAudioRecording,
    required this.hasAttachments,
    required this.onAttach,
    required this.onOpenMarkdownEditor,
    required this.onRecordAudio,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool recordingAudio;
  final String placeholder;
  final bool supportsAudioRecording;
  final bool hasAttachments;
  final VoidCallback onAttach;
  final VoidCallback onOpenMarkdownEditor;
  final VoidCallback onRecordAudio;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    final actions = _ComposerActionButtons(
      busy: busy,
      recordingAudio: recordingAudio,
      focusNode: focusNode,
      supportsAudioRecording: supportsAudioRecording,
      onAttach: onAttach,
      onOpenMarkdownEditor: onOpenMarkdownEditor,
      onRecordAudio: onRecordAudio,
      foregroundColor: colors.onSurfaceVariant,
      disabledForegroundColor: colors.muted.withOpacity(0.5),
    );
    final input = _ComposerTextInputShell(
      child: TextField(
        key: const ValueKey('chat_input'),
        controller: controller,
        focusNode: focusNode,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
        decoration: _composerTextInputDecoration(
          hintText: placeholder,
          hintStyle: AgentOperatingSystemTokens.bodyMd.copyWith(
            color: colors.muted,
          ),
        ),
        style: AgentOperatingSystemTokens.bodyMd.copyWith(
          color: colors.onSurface,
        ),
      ),
    );
    final send = _OperatingComposerSendButton(
      controller: controller,
      busy: busy,
      hasAttachments: hasAttachments,
      onSend: onSend,
      backgroundColor: colors.secondary,
      foregroundColor: colors.background,
      disabledBackgroundColor: colors.surfaceContainerHigh,
      disabledForegroundColor: colors.onSurfaceVariant.withOpacity(0.45),
      icon: Icons.arrow_upward_rounded,
      size: 40,
      radius: AgentOperatingSystemTokens.radiusMd,
    );

    return _ComposerResponsiveControls(
      actions: actions,
      input: input,
      send: send,
      recordingAudio: recordingAudio,
      onStopRecording: onStopRecording,
      onCancelRecording: onCancelRecording,
      compactBreakpoint: 500,
    );
  }
}
