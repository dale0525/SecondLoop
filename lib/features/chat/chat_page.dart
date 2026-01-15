import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../src/rust/db.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({required this.conversation, super.key});

  final Conversation conversation;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  Future<List<Message>>? _messagesFuture;
  bool _sending = false;
  bool _asking = false;
  bool _stopRequested = false;
  bool _thisThreadOnly = false;
  String? _pendingQuestion;
  String _streamingAnswer = '';
  String? _askError;
  StreamSubscription<String>? _askSub;

  @override
  void dispose() {
    _askSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<List<Message>> _loadMessages() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    return backend.listMessages(sessionKey, widget.conversation.id);
  }

  void _refresh() {
    setState(() {
      _messagesFuture = _loadMessages();
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_asking) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'user',
        content: text,
      );
      _controller.clear();
      _refresh();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _stopAsk() async {
    final sub = _askSub;
    if (!_asking || _stopRequested) return;

    setState(() {
      _stopRequested = true;
      _askSub = null;
      _asking = false;
      _pendingQuestion = null;
      _streamingAnswer = '';
    });

    if (sub != null) {
      unawaited(sub.cancel());
    }

    if (!mounted) return;
    setState(() => _stopRequested = false);
  }

  Future<void> _askAi() async {
    if (_asking) return;
    if (_sending) return;

    final question = _controller.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _asking = true;
      _stopRequested = false;
      _askError = null;
      _pendingQuestion = question;
      _streamingAnswer = '';
    });
    _controller.clear();

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    final stream = backend.askAiStream(
      sessionKey,
      widget.conversation.id,
      question: question,
      topK: 10,
      thisThreadOnly: _thisThreadOnly,
    );

    late final StreamSubscription<String> sub;
    sub = stream.listen(
      (delta) {
        if (!mounted) return;
        if (!identical(_askSub, sub)) return;
        setState(() => _streamingAnswer += delta);
      },
      onError: (e) {
        if (!mounted) return;
        if (!identical(_askSub, sub)) return;
        setState(() {
          _askError = '$e';
          _askSub = null;
          _asking = false;
          _pendingQuestion = null;
          _streamingAnswer = '';
        });
        _refresh();
      },
      onDone: () {
        if (!mounted) return;
        if (!identical(_askSub, sub)) return;
        setState(() {
          _askSub = null;
          _asking = false;
          _pendingQuestion = null;
          _streamingAnswer = '';
        });
        _refresh();
      },
      cancelOnError: true,
    );

    setState(() => _askSub = sub);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messagesFuture ??= _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conversation.title),
        actions: [
          PopupMenuButton<bool>(
            initialValue: _thisThreadOnly,
            onSelected: (value) => setState(() => _thisThreadOnly = value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: false,
                child: Text('Focus: All memories'),
              ),
              PopupMenuItem(
                value: true,
                child: Text('Focus: This thread'),
              ),
            ],
            icon: const Icon(Icons.filter_alt),
            tooltip: 'Focus',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder(
              future: _messagesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Load failed: ${snapshot.error}'));
                }

                final messages = snapshot.data ?? const <Message>[];
                final pendingQuestion = _pendingQuestion;
                final extraCount =
                    (pendingQuestion == null ? 0 : 1) + (_asking && !_stopRequested ? 1 : 0);
                if (messages.isEmpty && extraCount == 0) {
                  return const Center(child: Text('No messages yet'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length + extraCount,
                  itemBuilder: (context, index) {
                    Message? msg;
                    String? textOverride;
                    if (index < messages.length) {
                      msg = messages[index];
                    } else {
                      var extraIndex = index - messages.length;
                      if (pendingQuestion != null) {
                        if (extraIndex == 0) {
                          msg = Message(
                            id: 'pending_user',
                            conversationId: widget.conversation.id,
                            role: 'user',
                            content: pendingQuestion,
                            createdAtMs: 0,
                          );
                        }
                        extraIndex -= 1;
                      }
                      if (msg == null && _asking && !_stopRequested && extraIndex == 0) {
                        msg = Message(
                          id: 'pending_assistant',
                          conversationId: widget.conversation.id,
                          role: 'assistant',
                          content: '',
                          createdAtMs: 0,
                        );
                        textOverride = _streamingAnswer.isEmpty ? '…' : _streamingAnswer;
                      }
                    }

                    if (msg == null) return const SizedBox.shrink();
                    final isUser = msg.role == 'user';
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(textOverride ?? msg.content),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_askError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                _askError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat_input'),
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('chat_send'),
                    onPressed: (_sending || _asking) ? null : _send,
                    child: const Text('Send'),
                  ),
                  const SizedBox(width: 8),
                  if (_asking)
                    OutlinedButton(
                      key: const ValueKey('chat_stop'),
                      onPressed: _stopRequested ? null : _stopAsk,
                      child: Text(_stopRequested ? 'Stopping…' : 'Stop'),
                    )
                  else
                    FilledButton.tonal(
                      key: const ValueKey('chat_ask_ai'),
                      onPressed: (_sending || _asking) ? null : _askAi,
                      child: const Text('Ask AI'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
