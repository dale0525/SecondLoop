import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/ai/ai_routing.dart';
import '../core/backend/cloud_web_backend.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../features/chat/message_viewer_page.dart';
import '../i18n/strings.g.dart';
import '../src/rust/db.dart';

import 'web_app_service.dart';
import 'web_formal_settings_adapters.dart';

class WebChatPage extends StatefulWidget {
  const WebChatPage({
    required this.service,
    required this.authController,
    required this.chatBackend,
    super.key,
  });

  final WebAppService service;
  final CloudAuthController authController;
  final CloudWebBackend chatBackend;

  @override
  State<WebChatPage> createState() => _WebChatPageState();
}

class _WebChatPageState extends State<WebChatPage> {
  String _formatCloudChatError(BuildContext context, Object error) {
    final t = context.t;
    final status = parseHttpStatusFromError(error);
    final code = parseCloudErrorCodeFromError(error);
    if (code == 'email_not_verified') {
      return t.chat.cloudGateway.emailNotVerified;
    }
    if (status == 401) {
      return t.chat.cloudGateway.errors.auth;
    }
    if (status == 402 || code == 'payment_required') {
      return t.chat.cloudGateway.errors.entitlement;
    }
    if (status == 429) {
      return t.chat.cloudGateway.errors.rateLimited;
    }
    return t.chat.cloudGateway.errors.generic;
  }

  final TextEditingController _controller = TextEditingController();
  final Uint8List _sessionKey = Uint8List(0);
  List<Message> _messages = const <Message>[];
  String? _conversationId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureConversationLoaded());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String> _ensureConversationId() async {
    if (_conversationId != null) return _conversationId!;
    final conversation =
        await widget.chatBackend.getOrCreateLoopHomeConversation(_sessionKey);
    _conversationId = conversation.id;
    return conversation.id;
  }

  Future<void> _ensureConversationLoaded() async {
    try {
      final conversationId = await _ensureConversationId();
      final messages = await widget.chatBackend.listMessages(
        _sessionKey,
        conversationId,
      );
      if (!mounted) return;
      setState(() => _messages = messages);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _formatCloudChatError(context, error));
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final idToken = await widget.authController.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        if (!mounted) return;
        setState(() => _error = context.t.chat.cloudGateway.errors.auth);
        return;
      }
      final conversationId = await _ensureConversationId();
      if (!mounted) return;

      setState(() => _controller.clear());

      Object? sendError;
      try {
        await widget.chatBackend
            .askAiStreamCloudGateway(
              _sessionKey,
              conversationId,
              question: text,
              gatewayBaseUrl: kWebFormalSettingsBaseUrl,
              idToken: idToken,
              modelName: 'cloud',
            )
            .join();
      } catch (error) {
        sendError = error;
      }

      final messages = await widget.chatBackend.listMessages(
        _sessionKey,
        conversationId,
      );
      if (!mounted) return;

      setState(() {
        _messages = messages;
        _error = sendError == null
            ? null
            : _formatCloudChatError(context, sendError);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.role == 'user'
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Card(
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MessageViewerPage(
                              content: message.content,
                              messageId: message.id,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(message.content),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: context.t.app.web.chat.placeholder,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(context.t.app.web.chat.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
