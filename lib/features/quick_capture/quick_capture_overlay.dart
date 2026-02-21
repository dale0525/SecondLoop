import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/app_backend.dart';
import '../../core/quick_capture/quick_capture_controller.dart';
import '../../core/quick_capture/quick_capture_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_focus_ring.dart';
import '../actions/review/review_backoff.dart';
import '../actions/settings/actions_settings_store.dart';
import '../actions/suggestions_card.dart';
import '../actions/time/time_resolver.dart';

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
  final _textController = TextEditingController();
  bool _busy = false;

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

    setState(() => _busy = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final conversation =
          await backend.getOrCreateLoopHomeConversation(sessionKey);

      final message = await backend.insertMessage(
        sessionKey,
        conversation.id,
        role: 'user',
        content: text,
      );
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();

      final locale = Localizations.localeOf(context);
      final settings = await ActionsSettingsStore.load();
      final timeResolution = LocalTimeResolver.resolve(
        text,
        DateTime.now(),
        locale: locale,
        dayEndMinutes: settings.dayEndMinutes,
      );
      final looksLikeReview = LocalTimeResolver.looksLikeReviewIntent(text);

      if (timeResolution != null || looksLikeReview) {
        if (!mounted) return;
        final decision = await showCaptureTodoSuggestionSheet(
          context,
          title: text,
          timeResolution: timeResolution,
        );
        if (decision != null && mounted) {
          final todoId = 'todo:${message.id}';
          switch (decision) {
            case CaptureTodoScheduleDecision(:final dueAtLocal):
              await backend.upsertTodo(
                sessionKey,
                id: todoId,
                title: text,
                dueAtMs: dueAtLocal.toUtc().millisecondsSinceEpoch,
                status: 'open',
                sourceEntryId: message.id,
                reviewStage: null,
                nextReviewAtMs: null,
                lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
              );
              syncEngine?.notifyLocalMutation();
              break;
            case CaptureTodoReviewDecision():
              final nextLocal = ReviewBackoff.initialNextReviewAt(
                DateTime.now(),
                settings,
              );
              await backend.upsertTodo(
                sessionKey,
                id: todoId,
                title: text,
                dueAtMs: null,
                status: 'inbox',
                sourceEntryId: message.id,
                reviewStage: 0,
                nextReviewAtMs: nextLocal.toUtc().millisecondsSinceEpoch,
                lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
              );
              syncEngine?.notifyLocalMutation();
              break;
            case CaptureTodoNoThanksDecision():
              break;
          }
        }
      }

      _dismiss(reopenMainWindow: true, openChat: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: SlFocusRing(
                  key: const ValueKey('quick_capture_ring'),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextField(
                          key: const ValueKey('quick_capture_input'),
                          controller: _textController,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: context.t.common.fields.quickCapture,
                            border: InputBorder.none,
                            filled: false,
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                    ),
                  ),
                ),
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
