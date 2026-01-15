import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/app_backend.dart';
import '../../core/quick_capture/quick_capture_controller.dart';
import '../../core/quick_capture/quick_capture_scope.dart';
import '../../core/session/session_scope.dart';

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

  void _dismiss() => QuickCaptureScope.of(context).hide();

  Future<String> _resolveInboxConversationId(AppBackend backend, Uint8List key) async {
    final conversations = await backend.listConversations(key);
    for (final c in conversations) {
      if (c.title == 'Inbox') return c.id;
    }

    if (conversations.isNotEmpty) return conversations.first.id;
    return (await backend.createConversation(key, 'Inbox')).id;
  }

  Future<void> _submit() async {
    if (_busy) return;

    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _busy = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final conversationId = await _resolveInboxConversationId(backend, sessionKey);

      await backend.insertMessage(
        sessionKey,
        conversationId,
        role: 'user',
        content: text,
      );

      _dismiss();
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
            color: Colors.black54,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('quick_capture_input'),
                            controller: _textController,
                            autofocus: true,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              hintText: 'Quick capture',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('quick_capture_submit'),
                          onPressed: _busy ? null : _submit,
                          child: const Text('Save'),
                        ),
                      ],
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
