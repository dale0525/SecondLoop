import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shell_style.dart';
import '../../core/backend/app_backend.dart';
import '../../core/quick_capture/quick_capture_controller.dart';
import '../../core/quick_capture/quick_capture_scope.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_focus_ring.dart';
import '../agent_ui/agent_design_tokens.dart';

class QuickCaptureOverlay extends StatefulWidget {
  const QuickCaptureOverlay({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<QuickCaptureOverlay> createState() => _QuickCaptureOverlayState();
}

class _QuickCaptureOverlayState extends State<QuickCaptureOverlay> {
  QuickCaptureController? _controller;
  Route<void>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final controller = QuickCaptureScope.of(context);
    if (_controller == controller) return;

    _controller?.removeListener(_onControllerChanged);
    _controller = controller;
    controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_sync()));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    unawaited(_sync());
  }

  Future<void> _sync() async {
    if (!mounted) return;

    final controller = _controller;
    if (controller == null) return;

    if (controller.visible) {
      await _show();
      return;
    }

    _hide();
  }

  Future<void> _show() async {
    if (_route != null) return;

    final controller = _controller;
    if (controller == null || !controller.visible) return;

    final navigator = widget.navigatorKey.currentState;
    final navigatorContext = widget.navigatorKey.currentContext;
    if (navigator == null || navigatorContext == null) return;

    final route = DialogRoute<void>(
      context: navigatorContext,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      useSafeArea: false,
      builder: (_) => const _QuickCaptureDialog(),
    );
    _route = route;

    await navigator.push(route);

    _route = null;
    if (controller.visible) controller.hide();
  }

  void _hide() {
    final navigator = widget.navigatorKey.currentState;
    final route = _route;
    if (navigator == null || route == null) return;

    if (route.isCurrent) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class _QuickCaptureDialog extends StatefulWidget {
  const _QuickCaptureDialog();

  @override
  State<_QuickCaptureDialog> createState() => _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends State<_QuickCaptureDialog> {
  static const _danger = Color(0xFFB42318);
  static const _darkDanger = Color(0xFFFFB4AB);

  final _textController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _dismiss({
    bool reopenMainWindow = false,
    bool openChat = false,
  }) =>
      QuickCaptureScope.of(context).hide(
        reopenMainWindow: reopenMainWindow,
        openChat: openChat,
      );

  Future<void> _submit() async {
    if (_busy) return;

    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final conversation =
          await backend.getOrCreateLoopHomeConversation(sessionKey);
      if (!mounted) return;

      QuickCaptureScope.of(context).submitChatMessage(
        conversationId: conversation.id,
        content: text,
      );
    } catch (_) {
      if (!mounted) return;
      _showFailure();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFailure() {
    setState(() => _error = context.t.chat.askAiFailedTemporary);
  }

  @override
  Widget build(BuildContext context) {
    final conversationText = context.t.chat.agentConversation;
    final statusText = _error?.trim();
    final hasError = statusText != null && statusText.isNotEmpty;
    final colors = _QuickCaptureColors.of(context);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const _DismissIntent(),
      },
      child: Actions(
        actions: {
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) => _dismiss(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox.expand(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxHeight <= 140;
                  final outerPadding = isCompact
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                      : const EdgeInsets.fromLTRB(24, 24, 24, 0);

                  return Align(
                    alignment:
                        isCompact ? Alignment.center : Alignment.topCenter,
                    child: Padding(
                      padding: outerPadding,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isCompact ? constraints.maxWidth : 640.0,
                        ),
                        child: SlFocusRing(
                          key: const ValueKey('quick_capture_ring'),
                          borderRadius: BorderRadius.circular(
                            AgentDesignTokens.radiusLg,
                          ),
                          child: DecoratedBox(
                            key: const ValueKey('quick_capture_panel'),
                            decoration: BoxDecoration(
                              color: colors.panel,
                              borderRadius: BorderRadius.circular(
                                  AgentDesignTokens.radiusLg),
                              border: Border.all(color: colors.line),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.shadow,
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                              child: Row(
                                children: [
                                  const _QuickCaptureBrandMark(
                                    radius: AgentDesignTokens.radiusMd,
                                  ),
                                  const SizedBox(
                                      width: AgentDesignTokens.gapMd),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                context.t.common.fields
                                                    .quickCapture,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0,
                                                  height: 1.1,
                                                ).copyWith(color: colors.ink),
                                              ),
                                            ),
                                            const SizedBox(
                                                width: AgentDesignTokens.gapSm),
                                            const _QuickCaptureStatusDot(),
                                            const SizedBox(
                                                width: AgentDesignTokens.gapXs),
                                            Flexible(
                                              child: Text(
                                                hasError
                                                    ? statusText
                                                    : conversationText.ready,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: hasError
                                                      ? colors.danger
                                                      : colors.muted,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(
                                            height: AgentDesignTokens.gapXs),
                                        TextField(
                                          key: const ValueKey(
                                              'quick_capture_input'),
                                          controller: _textController,
                                          autofocus: true,
                                          minLines: 1,
                                          maxLines: 1,
                                          textInputAction: TextInputAction.done,
                                          decoration: InputDecoration(
                                            hintText:
                                                conversationText.composerHint,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            disabledBorder: InputBorder.none,
                                            filled: false,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            hintStyle: TextStyle(
                                              color: colors.muted
                                                  .withOpacity(0.78),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          style: TextStyle(
                                            color: colors.ink,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          onChanged: (_) {
                                            if (_error == null) return;
                                            setState(() => _error = null);
                                          },
                                          onSubmitted: (_) => _submit(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(
                                      width: AgentDesignTokens.gapMd),
                                  ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: _textController,
                                    builder: (context, value, child) {
                                      final enabled = !_busy &&
                                          value.text.trim().isNotEmpty;
                                      return IconButton.filled(
                                        key: const ValueKey(
                                            'quick_capture_submit'),
                                        tooltip: _busy
                                            ? conversationText.working
                                            : conversationText.send,
                                        onPressed: enabled ? _submit : null,
                                        style: IconButton.styleFrom(
                                          fixedSize: const Size(40, 40),
                                          backgroundColor: colors.action,
                                          foregroundColor:
                                              colors.actionForeground,
                                          disabledBackgroundColor:
                                              colors.disabledAction,
                                          disabledForegroundColor:
                                              colors.muted.withOpacity(0.56),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AgentDesignTokens.radiusMd,
                                            ),
                                          ),
                                        ),
                                        icon: _busy
                                            ? const SizedBox.square(
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppShellPalette.panel,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.send_rounded,
                                                size: 18,
                                              ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

final class _QuickCaptureBrandMark extends StatelessWidget {
  const _QuickCaptureBrandMark({
    required this.radius,
  });

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = _QuickCaptureColors.of(context);
    return DecoratedBox(
      key: const ValueKey('quick_capture_brand_mark'),
      decoration: BoxDecoration(
        color: colors.action,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox.square(
        dimension: 32,
        child: Icon(
          Icons.all_inclusive_rounded,
          color: colors.actionForeground,
          size: 20,
        ),
      ),
    );
  }
}

@immutable
final class _QuickCaptureColors {
  const _QuickCaptureColors({
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.action,
    required this.actionForeground,
    required this.disabledAction,
    required this.danger,
    required this.shadow,
  });

  final Color panel;
  final Color ink;
  final Color muted;
  final Color line;
  final Color action;
  final Color actionForeground;
  final Color disabledAction;
  final Color danger;
  final Color shadow;

  static _QuickCaptureColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  static const light = _QuickCaptureColors(
    panel: AppShellPalette.panel,
    ink: AppShellPalette.ink,
    muted: AppShellPalette.muted,
    line: AppShellPalette.line,
    action: AppShellPalette.blue,
    actionForeground: AppShellPalette.panel,
    disabledAction: AppShellPalette.selected,
    danger: _QuickCaptureDialogState._danger,
    shadow: Color(0x140B5CF6),
  );

  static const dark = _QuickCaptureColors(
    panel: AppShellPalette.darkPanel,
    ink: AppShellPalette.darkInk,
    muted: AppShellPalette.darkMuted,
    line: AppShellPalette.darkLine,
    action: AppShellPalette.darkBlue,
    actionForeground: AppShellPalette.darkSoft,
    disabledAction: AppShellPalette.darkSurface,
    danger: _QuickCaptureDialogState._darkDanger,
    shadow: Color(0x66000000),
  );
}

final class _QuickCaptureStatusDot extends StatelessWidget {
  const _QuickCaptureStatusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('quick_capture_status_dot'),
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFF08A86B),
        shape: BoxShape.circle,
      ),
    );
  }
}
