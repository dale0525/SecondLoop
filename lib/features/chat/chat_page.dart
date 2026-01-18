import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
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
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;

  void _attachSyncEngine() {
    final engine = SyncEngineScope.maybeOf(context);
    if (identical(engine, _syncEngine)) return;

    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }

    _syncEngine = engine;
    if (engine == null) {
      _syncListener = null;
      return;
    }

    void onSyncChange() {
      if (!mounted) return;
      _refresh();
    }

    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  Future<void> _showMessageActions(Message message) async {
    if (message.id.startsWith('pending_')) return;

    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('message_action_edit'),
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () => Navigator.of(context).pop(_MessageAction.edit),
              ),
              ListTile(
                key: const ValueKey('message_action_delete'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () => Navigator.of(context).pop(_MessageAction.delete),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    switch (action) {
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message);
        break;
      case null:
        break;
    }
  }

  Future<void> _editMessage(Message message) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);

    var draft = message.content;
    try {
      final newContent = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Edit message'),
            content: TextFormField(
              key: const ValueKey('edit_message_content'),
              initialValue: draft,
              autofocus: true,
              maxLines: null,
              onChanged: (value) => draft = value,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('edit_message_save'),
                onPressed: () => Navigator.of(context).pop(draft),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      final trimmed = newContent?.trim();
      if (trimmed == null) return;

      await backend.editMessage(sessionKey, message.id, trimmed);
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Message updated')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Edit failed: $e')));
    }
  }

  Future<void> _deleteMessage(Message message) async {
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final messenger = ScaffoldMessenger.of(context);

      await backend.setMessageDeleted(sessionKey, message.id, true);
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Message deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  void dispose() {
    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }
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
      final syncEngine = SyncEngineScope.maybeOf(context);
      await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'user',
        content: text,
      );
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
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

    try {
      await _prepareEmbeddingsForAskAi(backend, sessionKey);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _askError = '$e';
        _askSub = null;
        _asking = false;
        _pendingQuestion = null;
        _streamingAnswer = '';
      });
      _refresh();
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      return;
    }

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
        SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
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
        SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      },
      cancelOnError: true,
    );

    setState(() => _askSub = sub);
  }

  Future<void> _prepareEmbeddingsForAskAi(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    final status = ValueNotifier<String>('Preparing semantic search…');
    final elapsedSeconds = ValueNotifier<int>(0);
    var dialogShown = false;

    final elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds.value += 1;
    });

    final showTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      dialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (context, value, child) {
                    return Row(
                      children: [
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(value)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<int>(
                  valueListenable: elapsedSeconds,
                  builder: (context, value, child) {
                    return Text(
                      'Elapsed: ${value}s',
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
    });

    try {
      var totalProcessed = 0;
      while (true) {
        final processed = await backend
            .processPendingMessageEmbeddings(sessionKey, limit: 256);
        if (processed <= 0) break;
        totalProcessed += processed;
        status.value = 'Indexing messages… ($totalProcessed indexed)';
      }
    } finally {
      showTimer.cancel();
      elapsedTimer.cancel();
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      status.dispose();
      elapsedSeconds.dispose();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messagesFuture ??= _loadMessages();
    _attachSyncEngine();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Color.alphaBlend(
                colorScheme.primary.withOpacity(0.04),
                Theme.of(context).scaffoldBackgroundColor,
              ),
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: FutureBuilder(
                    future: _messagesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                            child: Text('Load failed: ${snapshot.error}'));
                      }

                      final messages = snapshot.data ?? const <Message>[];
                      final pendingQuestion = _pendingQuestion;
                      final extraCount = (pendingQuestion == null ? 0 : 1) +
                          (_asking && !_stopRequested ? 1 : 0);
                      if (messages.isEmpty && extraCount == 0) {
                        return const Center(child: Text('No messages yet'));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
                            if (msg == null &&
                                _asking &&
                                !_stopRequested &&
                                extraIndex == 0) {
                              msg = Message(
                                id: 'pending_assistant',
                                conversationId: widget.conversation.id,
                                role: 'assistant',
                                content: '',
                                createdAtMs: 0,
                              );
                              textOverride = _streamingAnswer.isEmpty
                                  ? '…'
                                  : _streamingAnswer;
                            }
                          }

                          final stableMsg = msg;
                          if (stableMsg == null) {
                            return const SizedBox.shrink();
                          }

                          final isUser = stableMsg.role == 'user';
                          final bubbleShape = RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: colorScheme.outlineVariant
                                  .withOpacity(isUser ? 0 : 0.65),
                            ),
                          );
                          final bubbleColor = isUser
                              ? colorScheme.primaryContainer
                              : colorScheme.surface;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisAlignment: isUser
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 560),
                                  child: Material(
                                    color: bubbleColor,
                                    shape: bubbleShape,
                                    child: InkWell(
                                      onLongPress: () =>
                                          _showMessageActions(stableMsg),
                                      borderRadius: BorderRadius.circular(18),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Text(
                                            textOverride ?? stableMsg.content),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_askError != null)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      _askError!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('chat_input'),
                                controller: _controller,
                                decoration: const InputDecoration(
                                  hintText: 'Message',
                                  border: InputBorder.none,
                                  filled: false,
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
                                child:
                                    Text(_stopRequested ? 'Stopping…' : 'Stop'),
                              )
                            else
                              FilledButton.tonal(
                                key: const ValueKey('chat_ask_ai'),
                                onPressed:
                                    (_sending || _asking) ? null : _askAi,
                                child: const Text('Ask AI'),
                              ),
                          ],
                        ),
                      ),
                    ),
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

enum _MessageAction {
  edit,
  delete,
}
