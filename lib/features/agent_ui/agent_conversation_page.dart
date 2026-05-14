import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/ai/ask_ai_source_prefs.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../actions/assistant_message_actions.dart';
import '../actions/calendar/event_deeplink.dart';
import '../actions/calendar/event_viewer_page.dart';
import '../actions/review/review_backoff.dart';
import '../actions/settings/actions_settings_store.dart';
import '../actions/suggestions_parser.dart';
import '../actions/suggestions_card.dart';
import '../actions/time/date_time_picker_dialog.dart';
import '../actions/time/time_resolver.dart';
import '../actions/todo/todo_deeplink.dart';
import '../actions/todo/todo_detail_page.dart';
import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_viewer_page.dart';
import '../conversation_cards/approval_preview_card.dart';
import '../conversation_cards/calendar_email_card.dart';
import '../conversation_cards/daily_brief_card.dart';
import '../conversation_cards/media_summary_card.dart';
import '../conversation_cards/research_brief_card.dart';
import '../conversation_context/conversation_context_rail.dart';
import '../chat/chat_answer_citation_controller.dart';
import '../chat/chat_answer_evidence_parser.dart';
import '../chat/chat_assistant_message_footer.dart';
import '../chat/chat_markdown_link_handler.dart';
import '../chat/chat_markdown_preview.dart';
import '../chat/message_deeplink.dart';
import '../chat/message_viewer_page.dart';
import 'agent_design_tokens.dart';
import 'agent_ui_acceptance_driver.dart';

part 'agent_assistant_text_message.dart';

final class AgentConversationPage extends StatefulWidget {
  const AgentConversationPage({
    required this.conversation,
    required this.isTabActive,
    super.key,
  });

  final Conversation conversation;
  final bool isTabActive;

  @override
  State<AgentConversationPage> createState() => _AgentConversationPageState();
}

final class _AgentConversationPageState extends State<AgentConversationPage> {
  static const _askAiErrorPrefix = '\u001eSL_ERROR\u001e';
  static const _askAiMetaPrefix = '\u001eSL_META\u001e';
  static const _askAiReasoningPrefix = '\u001eSL_REASONING\u001e';
  static const _askAiControlPrefix = '\u001eSL_';
  static const _blue = Color(0xFF0B5CF6);
  static const _ink = Color(0xFF101936);
  static const _muted = Color(0xFF63708A);
  static const _line = Color(0xFFE1E7F0);
  static const _soft = Color(0xFFF7F9FC);
  static const _panel = Color(0xFFFFFFFF);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  Future<List<Message>>? _messagesFuture;
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;
  List<Message> _messages = const <Message>[];
  String? _pendingUserContent;
  String _streamingAnswer = '';
  String _streamingReasoning = '';
  String? _askError;
  bool _sending = false;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messagesFuture ??= _loadMessages();
    _attachSyncEngine();
  }

  @override
  void dispose() {
    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<Message>> _loadMessages() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final messages =
        await backend.listMessages(sessionKey, widget.conversation.id);
    if (mounted) {
      setState(() => _messages = messages);
    }
    return messages;
  }

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
      setState(() {
        _messagesFuture = _loadMessages();
      });
    }

    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  Future<void> _send() async {
    if (_sending || _thinking) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final existingMessageIds = _messages.map((message) => message.id).toSet();

    setState(() {
      _sending = true;
      _thinking = true;
      _pendingUserContent = text;
      _streamingAnswer = '';
      _streamingReasoning = '';
      _askError = null;
    });
    _controller.clear();
    _scrollToLatest();

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final route = await _resolveAskAiRoute(
        backend: backend,
        sessionKey: sessionKey,
      );
      final stream = _openAskAiStream(
        backend: backend,
        sessionKey: sessionKey,
        question: text,
        route: route,
        topK: 10,
      );

      final streamResult = await _consumeAskAiStream(stream);
      if (!mounted) return;

      if (_isEmbeddingsQuotaStreamError(streamResult.streamError)) {
        _showAskFailure(
          message: context.t.chat.askAiRetrievalQuotaUnavailable,
        );
        return;
      }

      syncEngine?.notifyExternalChange();
      final latestMessages = await _loadMessages();
      if (!mounted) return;
      final hasNewUserMessage = latestMessages.any(
        (message) =>
            message.role == 'user' && !existingMessageIds.contains(message.id),
      );
      final hasNewAssistantMessage = latestMessages.any(
        (message) =>
            message.role == 'assistant' &&
            !existingMessageIds.contains(message.id) &&
            message.content.trim().isNotEmpty,
      );
      if (streamResult.streamError != null ||
          (!streamResult.sawVisibleDelta && !hasNewAssistantMessage)) {
        _showAskFailure(newUserMessageCommitted: hasNewUserMessage);
        return;
      }
      setState(() {
        _pendingUserContent = null;
        _streamingAnswer = '';
        _streamingReasoning = '';
        _thinking = false;
      });
      _scrollToLatest();
    } catch (_) {
      if (!mounted) return;
      _showAskFailure();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<({bool sawVisibleDelta, String? streamError})> _consumeAskAiStream(
    Stream<String> stream,
  ) async {
    var sawVisibleDelta = false;
    String? streamError;

    await for (final delta in stream) {
      if (!mounted) break;
      if (delta.isEmpty) continue;
      if (delta.startsWith(_askAiMetaPrefix)) {
        continue;
      }
      if (delta.startsWith(_askAiErrorPrefix)) {
        streamError = delta.substring(_askAiErrorPrefix.length).trim();
        break;
      }
      if (delta.startsWith(_askAiReasoningPrefix)) {
        final text = _extractReasoningDeltaText(
          delta.substring(_askAiReasoningPrefix.length),
        );
        if (text.isNotEmpty) {
          setState(() => _streamingReasoning += text);
          _scrollToLatest();
        }
        continue;
      }
      if (delta.startsWith(_askAiControlPrefix)) {
        continue;
      }
      sawVisibleDelta = true;
      setState(() {
        _streamingReasoning = '';
        _streamingAnswer += delta;
      });
      _scrollToLatest();
    }

    return (
      sawVisibleDelta: sawVisibleDelta,
      streamError: streamError,
    );
  }

  bool _isEmbeddingsQuotaStreamError(String? error) {
    final normalized = error?.trim() ?? '';
    if (normalized.isEmpty) return false;
    return normalized.contains('embeddings_token_quota_exceeded') ||
        normalized.contains('embeddings_input_token_quota_exceeded');
  }

  void _showAskFailure({
    String? message,
    bool newUserMessageCommitted = false,
  }) {
    setState(() {
      _askError = message ?? context.t.chat.askAiFailedTemporary;
      _thinking = false;
      _streamingAnswer = '';
      _streamingReasoning = '';
      if (newUserMessageCommitted) {
        _pendingUserContent = null;
      }
    });
  }

  Future<
      ({
        AskAiRouteKind route,
        String? cloudIdToken,
        CloudGatewayConfig cloudGatewayConfig,
      })> _resolveAskAiRoute({
    required AppBackend backend,
    required Uint8List sessionKey,
  }) async {
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudIdToken = await readCloudCapabilityIdToken(
      cloudAuthScope?.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );

    final defaultRoute = await decideAskAiRoute(
      backend,
      sessionKey,
      cloudIdToken: cloudIdToken,
      cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
      subscriptionStatus: subscriptionStatus,
    );

    AskAiSourcePreference preference;
    try {
      preference = await AskAiSourcePrefs.read();
    } catch (_) {
      preference = AskAiSourcePreference.auto;
    }

    var hasByokWhenCloudRoute = false;
    if (preference == AskAiSourcePreference.byok &&
        defaultRoute == AskAiRouteKind.cloudGateway) {
      try {
        hasByokWhenCloudRoute = await hasActiveLlmProfile(backend, sessionKey);
      } catch (_) {
        hasByokWhenCloudRoute = false;
      }
    }

    final route = applyAskAiSourcePreference(
      defaultRoute,
      preference,
      hasByokWhenCloudRoute: hasByokWhenCloudRoute,
    );

    return (
      route: route,
      cloudIdToken: cloudIdToken,
      cloudGatewayConfig: cloudGatewayConfig,
    );
  }

  Stream<String> _openAskAiStream({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String question,
    required int topK,
    required ({
      AskAiRouteKind route,
      String? cloudIdToken,
      CloudGatewayConfig cloudGatewayConfig,
    }) route,
  }) {
    switch (route.route) {
      case AskAiRouteKind.cloudGateway:
        final idToken = route.cloudIdToken?.trim() ?? '';
        if (idToken.isEmpty) {
          throw StateError('cloud_id_token_required');
        }
        return backend.askAiStreamCloudGateway(
          sessionKey,
          widget.conversation.id,
          question: question,
          topK: topK,
          gatewayBaseUrl: route.cloudGatewayConfig.baseUrl,
          idToken: idToken,
          modelName: route.cloudGatewayConfig.modelName,
        );
      case AskAiRouteKind.byok:
        return backend.askAiStream(
          sessionKey,
          widget.conversation.id,
          question: question,
          topK: topK,
        );
      case AskAiRouteKind.needsSetup:
        throw StateError('ask_ai_route_needs_setup');
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  List<Widget> _buildAcceptanceCards(
    AgentUiAcceptanceController? controller,
  ) {
    final acceptanceController = controller;
    if (acceptanceController == null ||
        !acceptanceController.hasConversationCards) {
      return const <Widget>[];
    }

    final approvalChange = acceptanceController.approvalChange;
    final mediaSummary = acceptanceController.mediaSummary;
    final dailyBrief = acceptanceController.dailyBrief;
    final calendarEmail = acceptanceController.calendarEmail;
    final researchEstimate = acceptanceController.researchEstimate;
    final researchResult = acceptanceController.researchResult;

    return <Widget>[
      if (approvalChange != null)
        ApprovalPreviewCard(
          change: approvalChange,
          onApprove: acceptanceController.resolveTaskChangeProposal,
          onReject: acceptanceController.resolveTaskChangeProposal,
        ),
      if (mediaSummary != null) MediaSummaryCard(data: mediaSummary),
      if (dailyBrief != null) DailyBriefCard(data: dailyBrief),
      if (calendarEmail != null) CalendarEmailCard(data: calendarEmail),
      if (researchEstimate != null)
        ResearchBudgetConfirmationCard(estimate: researchEstimate),
      if (researchResult != null) ResearchResultCard(result: researchResult),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: _blue,
        brightness: Brightness.light,
      ),
    );
    final acceptanceController = AgentUiAcceptanceScope.maybeOf(context);
    final acceptanceCards = _buildAcceptanceCards(acceptanceController);
    final contextSnapshot = acceptanceController?.contextSnapshot ??
        const ConversationContextSnapshot.empty();

    return Theme(
      data: theme,
      child: Material(
        color: _soft,
        child: ColoredBox(
          key: const ValueKey('agent_conversation_workspace'),
          color: _soft,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showContext = constraints.maxWidth >= 680;
              final contextWidth = constraints.maxWidth < 900 ? 260.0 : 320.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildConversationPane(
                      context,
                      acceptanceCards: acceptanceCards,
                    ),
                  ),
                  if (showContext) ...[
                    const VerticalDivider(width: 1, color: _line),
                    SizedBox(
                      width: contextWidth,
                      child: ColoredBox(
                        color: _panel,
                        child: ConversationContextRail(
                          snapshot: contextSnapshot,
                          compact: true,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildConversationPane(
    BuildContext context, {
    required List<Widget> acceptanceCards,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          const SizedBox(height: AgentDesignTokens.gapXl),
          Expanded(
            child: FutureBuilder<List<Message>>(
              future: _messagesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done &&
                    _messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError && _messages.isEmpty) {
                  return _EmptyState(
                    title:
                        context.t.chat.agentConversation.conversationLoadFailed,
                    subtitle: '${snapshot.error}',
                  );
                }
                return _MessageList(
                  controller: _scrollController,
                  messages: _messages,
                  thinking: _thinking,
                  acceptanceCards: acceptanceCards,
                  pendingUserContent: _pendingUserContent,
                  streamingAnswer: _streamingAnswer,
                  streamingReasoning: _streamingReasoning,
                  askError: _askError,
                );
              },
            ),
          ),
          const SizedBox(height: AgentDesignTokens.gapLg),
          _Composer(
            controller: _controller,
            focusNode: _focusNode,
            busy: _sending || _thinking,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.agentConversation;
    return Row(
      children: [
        Expanded(
          child: Text(
            context.t.app.tabs.conversation,
            style: const TextStyle(
              color: _AgentConversationPageState._ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        const _PresenceDot(),
        const SizedBox(width: 8),
        Text(
          t.ready,
          style: const TextStyle(
            color: _AgentConversationPageState._ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

final class _PresenceDot extends StatelessWidget {
  const _PresenceDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: Color(0xFF08A86B),
        shape: BoxShape.circle,
      ),
    );
  }
}

final class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.messages,
    required this.thinking,
    required this.acceptanceCards,
    required this.pendingUserContent,
    required this.streamingAnswer,
    required this.streamingReasoning,
    required this.askError,
  });

  final ScrollController controller;
  final List<Message> messages;
  final bool thinking;
  final List<Widget> acceptanceCards;
  final String? pendingUserContent;
  final String streamingAnswer;
  final String streamingReasoning;
  final String? askError;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.agentConversation;
    final pendingContent = pendingUserContent?.trim();
    final streamingContent = streamingAnswer.trim();
    final errorContent = askError?.trim();
    final hasConversationContent = messages.isNotEmpty ||
        acceptanceCards.isNotEmpty ||
        thinking ||
        (pendingContent?.isNotEmpty ?? false) ||
        streamingContent.isNotEmpty ||
        (errorContent?.isNotEmpty ?? false);
    final children = <Widget>[
      if (!hasConversationContent)
        _EmptyState(
          title: context.t.chat.noMessagesYet,
          subtitle: t.composerHint,
        ),
      if (acceptanceCards.isNotEmpty)
        _MessageFrame(
          author: context.t.app.title,
          time: t.ready,
          child: _AcceptanceCardStack(cards: acceptanceCards),
        ),
      for (final message in messages)
        if (message.role == 'assistant')
          _AssistantTextMessage(
            content: message.content,
            time: t.done,
            sourceMessage: message,
          )
        else
          _UserMessage(content: message.content),
      if (pendingContent != null && pendingContent.isNotEmpty)
        _UserMessage(content: pendingContent),
      if (streamingContent.isNotEmpty)
        _AssistantTextMessage(content: streamingContent, time: t.thinking)
      else if (thinking)
        _ThinkingMessage(reasoning: streamingReasoning),
      if (errorContent != null && errorContent.isNotEmpty)
        _AssistantTextMessage(content: errorContent, time: t.done),
    ];

    return ListView.separated(
      key: const ValueKey('managed_pro_agent_message_list'),
      controller: controller,
      padding: EdgeInsets.zero,
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 18),
      itemBuilder: (context, index) => children[index],
    );
  }
}

final class _AcceptanceCardStack extends StatelessWidget {
  const _AcceptanceCardStack({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < cards.length; index++) ...[
          cards[index],
          if (index < cards.length - 1)
            const SizedBox(height: AgentDesignTokens.gapMd),
        ],
      ],
    );
  }
}

final class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.agentConversation;
    return _MessageFrame(
      author: t.you,
      time: t.now,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
              border: Border.all(color: const Color(0xFFBFD2FF)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AgentDesignTokens.gapLg,
                vertical: AgentDesignTokens.gapMd,
              ),
              child: Text(
                content,
                style: const TextStyle(
                  color: _AgentConversationPageState._ink,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ThinkingMessage extends StatelessWidget {
  const _ThinkingMessage({required this.reasoning});

  final String reasoning;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.agentConversation;
    final trimmedReasoning = reasoning.trim();
    final visibleReasoning = trimmedReasoning.length > 520
        ? trimmedReasoning.substring(trimmedReasoning.length - 520)
        : trimmedReasoning;

    return KeyedSubtree(
      key: const ValueKey('agent_thinking_panel'),
      child: _MessageFrame(
        author: context.t.app.title,
        time: t.thinking,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
            border: Border.all(color: _AgentConversationPageState._line),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AgentDesignTokens.gapLg,
              vertical: AgentDesignTokens.gapMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.thinking,
                  style: const TextStyle(
                    color: _AgentConversationPageState._ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AgentDesignTokens.gapXs),
                if (visibleReasoning.isEmpty)
                  Text(
                    t.thinkingBody,
                    style: const TextStyle(
                      color: _AgentConversationPageState._muted,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    visibleReasoning,
                    key: const ValueKey('agent_thinking_reasoning_text'),
                    maxLines: 4,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(
                      color: _AgentConversationPageState._muted,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _extractReasoningDeltaText(String rawPayload) {
  try {
    final decoded = jsonDecode(rawPayload);
    if (decoded is Map) {
      return '${decoded['text'] ?? ''}';
    }
  } catch (_) {
    return '';
  }
  return '';
}

final class _MessageFrame extends StatelessWidget {
  const _MessageFrame({
    required this.author,
    required this.time,
    required this.child,
  });

  final String author;
  final String time;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Avatar(),
        const SizedBox(width: AgentDesignTokens.gapMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    author,
                    style: const TextStyle(
                      color: _AgentConversationPageState._ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: AgentDesignTokens.gapMd),
                  Text(
                    time,
                    style: const TextStyle(
                      color: _AgentConversationPageState._muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AgentDesignTokens.gapSm),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

final class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(
        color: _AgentConversationPageState._blue,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 19),
      ),
    );
  }
}

final class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.agentConversation;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AgentConversationPageState._panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AgentConversationPageState._line),
        boxShadow: [
          BoxShadow(
            color: _AgentConversationPageState._blue.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('chat_input'),
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: t.composerHint,
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: const TextStyle(
                  color: _AgentConversationPageState._ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: t.attach,
              onPressed: busy ? null : () {},
              icon: const Icon(Icons.add_rounded),
            ),
            IconButton(
              tooltip: t.record,
              onPressed: busy ? null : () {},
              icon: const Icon(Icons.mic_none_rounded),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, child) {
                final enabled = !busy && value.text.trim().isNotEmpty;
                return FilledButton.icon(
                  key: const ValueKey('chat_send'),
                  onPressed: enabled ? onSend : null,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(busy ? t.working : t.send),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: AgentDesignTokens.gapSm),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _AgentConversationPageState._muted,
            ),
          ),
        ],
      ),
    );
  }
}
