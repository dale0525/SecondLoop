import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../attachments/attachment_card.dart';
import '../attachments/attachment_viewer_page.dart';
import '../settings/cloud_account_page.dart';
import '../settings/llm_profiles_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({required this.conversation, super.key});

  final Conversation conversation;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  Future<List<Message>>? _messagesFuture;
  final Map<String, Future<List<Attachment>>> _attachmentsFuturesByMessageId =
      <String, Future<List<Attachment>>>{};
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

  static const _kAskAiDataConsentPrefsKey = 'ask_ai_data_consent_v1';
  static const _kAskAiCloudFallbackSnackKey = ValueKey(
    'ask_ai_cloud_fallback_snack',
  );
  static const _kAskAiEmailNotVerifiedSnackKey = ValueKey(
    'ask_ai_email_not_verified_snack',
  );

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
                title: Text(context.t.common.actions.edit),
                onTap: () => Navigator.of(context).pop(_MessageAction.edit),
              ),
              ListTile(
                key: const ValueKey('message_action_delete'),
                leading: const Icon(Icons.delete_outline),
                title: Text(context.t.common.actions.delete),
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
            title: Text(context.t.chat.editMessageTitle),
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
                child: Text(context.t.common.actions.cancel),
              ),
              FilledButton(
                key: const ValueKey('edit_message_save'),
                onPressed: () => Navigator.of(context).pop(draft),
                child: Text(context.t.common.actions.save),
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
      messenger.showSnackBar(
        SnackBar(content: Text(context.t.chat.messageUpdated)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.t.chat.editFailed(error: '$e'))),
      );
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
      messenger.showSnackBar(
        SnackBar(content: Text(context.t.chat.messageDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.chat.deleteFailed(error: '$e'))),
      );
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
      _attachmentsFuturesByMessageId.clear();
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

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    String? cloudIdToken;
    try {
      cloudIdToken = await cloudAuthScope?.controller.getIdToken();
    } catch (_) {
      cloudIdToken = null;
    }

    if (!mounted) return;
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;

    final route = await decideAskAiRoute(
      backend,
      sessionKey,
      cloudIdToken: cloudIdToken,
      cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
      subscriptionStatus: subscriptionStatus,
    );

    if (route == AskAiRouteKind.needsSetup) {
      final configured = await _ensureAskAiConfigured(backend, sessionKey);
      if (!configured) return;
    }

    final consented = await _ensureAskAiDataConsent();
    if (!consented) return;

    setState(() {
      _asking = true;
      _stopRequested = false;
      _askError = null;
      _pendingQuestion = question;
      _streamingAnswer = '';
    });
    _controller.clear();

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

    Stream<String> stream;
    switch (route) {
      case AskAiRouteKind.cloudGateway:
        stream = backend.askAiStreamCloudGateway(
          sessionKey,
          widget.conversation.id,
          question: question,
          topK: 10,
          thisThreadOnly: _thisThreadOnly,
          gatewayBaseUrl: cloudGatewayConfig.baseUrl,
          idToken: cloudIdToken ?? '',
          modelName: cloudGatewayConfig.modelName,
        );
        break;
      case AskAiRouteKind.byok:
      case AskAiRouteKind.needsSetup:
        stream = backend.askAiStream(
          sessionKey,
          widget.conversation.id,
          question: question,
          topK: 10,
          thisThreadOnly: _thisThreadOnly,
        );
        break;
    }

    Future<void> startStream(Stream<String> stream,
        {required bool fromCloud}) async {
      late final StreamSubscription<String> sub;
      sub = stream.listen(
        (delta) {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          setState(() => _streamingAnswer += delta);
        },
        onError: (e) async {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;

          if (fromCloud && isCloudEmailNotVerifiedError(e)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: _kAskAiEmailNotVerifiedSnackKey,
                content: Text(context.t.chat.cloudGateway.emailNotVerified),
                action: SnackBarAction(
                  label: context.t.settings.cloudAccount.title,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const CloudAccountPage(),
                      ),
                    );
                  },
                ),
              ),
            );

            if (!mounted) return;
            setState(() {
              _askError = null;
              _askSub = null;
              _asking = false;
              _pendingQuestion = null;
              _streamingAnswer = '';
            });
            _refresh();
            SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
            return;
          }

          final cloudStatus = fromCloud ? parseHttpStatusFromError(e) : null;

          final hasByok = await hasActiveLlmProfile(backend, sessionKey);
          if (!mounted) return;
          if (fromCloud && hasByok && isCloudFallbackableError(e)) {
            final message = switch (cloudStatus) {
              401 => context.t.chat.cloudGateway.fallback.auth,
              402 => context.t.chat.cloudGateway.fallback.entitlement,
              429 => context.t.chat.cloudGateway.fallback.rateLimited,
              _ => context.t.chat.cloudGateway.fallback.generic,
            };

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: _kAskAiCloudFallbackSnackKey,
                content: Text(message),
              ),
            );

            if (!mounted) return;
            setState(() {
              _askError = null;
              _streamingAnswer = '';
            });

            final byokStream = backend.askAiStream(
              sessionKey,
              widget.conversation.id,
              question: question,
              topK: 10,
              thisThreadOnly: _thisThreadOnly,
            );
            await startStream(byokStream, fromCloud: false);
            return;
          }

          if (!mounted) return;
          setState(() {
            _askError = fromCloud
                ? switch (cloudStatus) {
                    401 => context.t.chat.cloudGateway.errors.auth,
                    402 => context.t.chat.cloudGateway.errors.entitlement,
                    429 => context.t.chat.cloudGateway.errors.rateLimited,
                    _ => context.t.chat.cloudGateway.errors.generic,
                  }
                : '$e';
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

      if (!mounted) return;
      setState(() => _askSub = sub);
    }

    await startStream(stream, fromCloud: route == AskAiRouteKind.cloudGateway);
  }

  Future<bool> _ensureAskAiDataConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final skip = prefs.getBool(_kAskAiDataConsentPrefsKey) ?? false;
    if (skip) return true;
    if (!mounted) return false;

    var dontShowAgain = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = context.t;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              key: const ValueKey('ask_ai_consent_dialog'),
              title: Text(t.chat.askAiConsent.title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.chat.askAiConsent.body),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const ValueKey('ask_ai_consent_dont_show_again'),
                    contentPadding: EdgeInsets.zero,
                    value: dontShowAgain,
                    onChanged: (value) {
                      setState(() => dontShowAgain = value ?? false);
                    },
                    title: Text(t.chat.askAiConsent.dontShowAgain),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.common.actions.cancel),
                ),
                FilledButton(
                  key: const ValueKey('ask_ai_consent_continue'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.common.actions.continueLabel),
                ),
              ],
            );
          },
        );
      },
    );

    if (approved != true) return false;
    if (dontShowAgain) {
      await prefs.setBool(_kAskAiDataConsentPrefsKey, true);
    }
    return true;
  }

  Future<bool> _ensureAskAiConfigured(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    try {
      final hasActiveProfile = await hasActiveLlmProfile(backend, sessionKey);
      if (hasActiveProfile) return true;
    } catch (_) {
      return true;
    }
    if (!mounted) return false;

    final action = await showDialog<_AskAiSetupAction>(
      context: context,
      builder: (context) {
        final t = context.t;
        return AlertDialog(
          key: const ValueKey('ask_ai_setup_dialog'),
          title: Text(t.chat.askAiSetup.title),
          content: Text(t.chat.askAiSetup.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.common.actions.cancel),
            ),
            TextButton(
              key: const ValueKey('ask_ai_setup_subscribe'),
              onPressed: () =>
                  Navigator.of(context).pop(_AskAiSetupAction.subscribe),
              child: Text(t.chat.askAiSetup.actions.subscribe),
            ),
            FilledButton(
              key: const ValueKey('ask_ai_setup_configure_byok'),
              onPressed: () =>
                  Navigator.of(context).pop(_AskAiSetupAction.configureByok),
              child: Text(t.chat.askAiSetup.actions.configureByok),
            ),
          ],
        );
      },
    );

    if (!mounted) return false;

    switch (action) {
      case _AskAiSetupAction.configureByok:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
        );
        break;
      case _AskAiSetupAction.subscribe:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CloudAccountPage()),
        );
        break;
      case null:
        break;
    }

    return false;
  }

  Future<void> _prepareEmbeddingsForAskAi(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    final t = context.t;
    final status = ValueNotifier<String>(t.semanticSearch.preparing);
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
                      context.t.common.labels.elapsedSeconds(seconds: value),
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
        status.value = t.semanticSearch.indexingMessages(count: totalProcessed);
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
    final title = widget.conversation.id == 'main_stream'
        ? context.t.chat.mainStreamTitle
        : widget.conversation.title;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<bool>(
            initialValue: _thisThreadOnly,
            onSelected: (value) => setState(() => _thisThreadOnly = value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: false,
                child: Text(context.t.chat.focus.allMemories),
              ),
              PopupMenuItem(
                value: true,
                child: Text(context.t.chat.focus.thisThread),
              ),
            ],
            icon: const Icon(Icons.filter_alt),
            tooltip: context.t.chat.focus.tooltip,
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
                          child: Text(
                            context.t.errors
                                .loadFailed(error: '${snapshot.error}'),
                          ),
                        );
                      }

                      final messages = snapshot.data ?? const <Message>[];
                      final pendingQuestion = _pendingQuestion;
                      final extraCount = (pendingQuestion == null ? 0 : 1) +
                          (_asking && !_stopRequested ? 1 : 0);
                      if (messages.isEmpty && extraCount == 0) {
                        return Center(
                          child: Text(context.t.chat.noMessagesYet),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: messages.length + extraCount,
                        itemBuilder: (context, index) {
                          final backend = AppBackendScope.of(context);
                          final attachmentsBackend =
                              backend is AttachmentsBackend
                                  ? backend as AttachmentsBackend
                                  : null;
                          final sessionKey =
                              SessionScope.of(context).sessionKey;

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

                          final supportsAttachments =
                              attachmentsBackend != null &&
                                  !stableMsg.id.startsWith('pending_');

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
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(textOverride ??
                                                stableMsg.content),
                                            if (supportsAttachments)
                                              FutureBuilder(
                                                future:
                                                    _attachmentsFuturesByMessageId
                                                        .putIfAbsent(
                                                  stableMsg.id,
                                                  () => attachmentsBackend
                                                      .listMessageAttachments(
                                                    sessionKey,
                                                    stableMsg.id,
                                                  ),
                                                ),
                                                builder: (context, snapshot) {
                                                  final items = snapshot.data ??
                                                      const <Attachment>[];
                                                  if (items.isEmpty) {
                                                    return const SizedBox
                                                        .shrink();
                                                  }

                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      top: 8,
                                                    ),
                                                    child:
                                                        SingleChildScrollView(
                                                      scrollDirection:
                                                          Axis.horizontal,
                                                      child: Row(
                                                        children: [
                                                          for (final attachment
                                                              in items)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                right: 8,
                                                              ),
                                                              child:
                                                                  AttachmentCard(
                                                                attachment:
                                                                    attachment,
                                                                onTap: () {
                                                                  Navigator.of(
                                                                          context)
                                                                      .push(
                                                                    MaterialPageRoute(
                                                                      builder:
                                                                          (context) {
                                                                        return AttachmentViewerPage(
                                                                          attachment:
                                                                              attachment,
                                                                        );
                                                                      },
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                        ],
                                                      ),
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
                                decoration: InputDecoration(
                                  hintText: context.t.common.fields.message,
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
                              child: Text(context.t.common.actions.send),
                            ),
                            const SizedBox(width: 8),
                            if (_asking)
                              OutlinedButton(
                                key: const ValueKey('chat_stop'),
                                onPressed: _stopRequested ? null : _stopAsk,
                                child: Text(
                                  _stopRequested
                                      ? context.t.common.actions.stopping
                                      : context.t.common.actions.stop,
                                ),
                              )
                            else
                              FilledButton.tonal(
                                key: const ValueKey('chat_ask_ai'),
                                onPressed:
                                    (_sending || _asking) ? null : _askAi,
                                child: Text(context.t.common.actions.askAi),
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

enum _AskAiSetupAction {
  subscribe,
  configureByok,
}
