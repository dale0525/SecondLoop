import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web chat send guards concurrent sends before auth awaits', () {
    final source = File('lib/web_app/web_chat_page.dart').readAsStringSync();

    expect(
      source,
      contains('''if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final idToken = await widget.authController.getIdToken();'''),
    );
  });

  test('web chat initial load surfaces backend failures inline', () {
    final source = File('lib/web_app/web_chat_page.dart').readAsStringSync();

    expect(
        source, contains('Future<void> _ensureConversationLoaded() async {'));
    expect(source, contains('try {'));
    expect(source,
        contains('final conversationId = await _ensureConversationId();'));
    expect(source,
        contains('final messages = await widget.chatBackend.listMessages('));
    expect(source, contains('setState(() => _messages = messages);'));
    expect(
        source,
        contains(
            'setState(() => _error = _formatCloudChatError(context, error));'));
  });

  test('web chat send guards setState after async auth gaps', () {
    final source = File('lib/web_app/web_chat_page.dart').readAsStringSync();

    expect(
      source,
      contains('''final idToken = await widget.authController.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        if (!mounted) return;
        setState(() => _error = context.t.chat.cloudGateway.errors.auth);
        return;
      }
      final conversationId = await _ensureConversationId();
      if (!mounted) return;

      setState(() => _controller.clear());'''),
    );
    expect(source, contains('finally {'));
    expect(source, contains("setState(() => _busy = false);"));
  });
}
