import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/secretary_backend.dart';
import '../../core/cloud/runtime_secretary_app_service.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/secretary_runtime_client.dart';
import '../../core/cloud/secretary_runtime_conversation_sender.dart';
import '../../core/quick_capture/quick_capture_controller.dart';
import '../../core/quick_capture/quick_capture_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
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
import 'agent_conversation_send.dart';
import 'agent_status_chip.dart';
import 'agent_task_summary.dart';
import 'agent_ui_acceptance_driver.dart';

part 'agent_assistant_text_message.dart';
part 'agent_conversation_widgets.dart';

final class AgentConversationPage extends StatefulWidget {
  const AgentConversationPage({
    required this.conversation,
    required this.isTabActive,
    this.runtimeConversationSender,
    super.key,
  });

  final Conversation conversation;
  final bool isTabActive;
  final ChatRuntimeConversationSender? runtimeConversationSender;

  @override
  State<AgentConversationPage> createState() => _AgentConversationPageState();
}

final class _AgentConversationPageState extends State<AgentConversationPage> {
  static const _blue = Color(0xFF0B5CF6);
  static const _ink = Color(0xFF101936);
  static const _muted = Color(0xFF63708A);
  static const _line = Color(0xFFE1E7F0);
  static const _soft = Color(0xFFF7F9FC);
  static const _panel = Color(0xFFFFFFFF);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _messageListBottomKey = GlobalKey();
  Future<List<Message>>? _messagesFuture;
  Future<List<Todo>>? _tasksFuture;
  Future<List<MemoryPageRecord>>? _memoryPagesFuture;
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;
  QuickCaptureController? _quickCaptureController;
  List<Message> _messages = const <Message>[];
  List<Todo> _todos = const <Todo>[];
  List<MemoryPageRecord> _memoryPages = const <MemoryPageRecord>[];
  String? _pendingUserContent;
  String _streamingAnswer = '';
  String _streamingReasoning = '';
  String? _askError;
  List<SecretaryRuntimeApprovalItem> _runtimeApprovalItems =
      const <SecretaryRuntimeApprovalItem>[];
  final Set<String> _busyApprovalIds = <String>{};
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
    _tasksFuture ??= _loadTasks();
    _memoryPagesFuture ??= _loadMemoryPages();
    _attachSyncEngine();
    _attachQuickCaptureController();
  }

  @override
  void dispose() {
    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }
    _quickCaptureController?.removeListener(_onQuickCaptureChanged);
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
      _scrollToLatest();
    }
    return messages;
  }

  Future<List<Todo>> _loadTasks() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } on UnimplementedError {
      return const <Todo>[];
    } on UnsupportedError {
      return const <Todo>[];
    }
    if (mounted) {
      setState(() => _todos = todos);
    }
    return todos;
  }

  Future<List<MemoryPageRecord>> _loadMemoryPages() async {
    final backend = AppBackendScope.of(context);
    if (backend is! SecretaryBackend) return const <MemoryPageRecord>[];
    final secretaryBackend = backend as SecretaryBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    final List<MemoryPageRecord> pages;
    try {
      pages = await secretaryBackend.listMemoryPages(
        sessionKey,
        state: 'active',
      );
    } on UnimplementedError {
      return const <MemoryPageRecord>[];
    } on UnsupportedError {
      return const <MemoryPageRecord>[];
    }
    if (mounted) {
      setState(() => _memoryPages = pages);
    }
    return pages;
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
        _tasksFuture = _loadTasks();
        _memoryPagesFuture = _loadMemoryPages();
      });
    }

    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  void _attachQuickCaptureController() {
    final controller = QuickCaptureScope.maybeOf(context);
    if (identical(controller, _quickCaptureController)) return;

    _quickCaptureController?.removeListener(_onQuickCaptureChanged);
    _quickCaptureController = controller;
    controller?.addListener(_onQuickCaptureChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onQuickCaptureChanged();
    });
  }

  void _onQuickCaptureChanged() {
    if (_sending || _thinking) return;
    final submission = _quickCaptureController?.consumePendingChatSubmission(
      widget.conversation.id,
    );
    final text = submission?.content.trim();
    if (text == null || text.isEmpty) return;
    unawaited(_sendText(text));
  }

  Future<void> _send() async {
    if (_sending || _thinking) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await _sendText(text);
  }

  Future<void> _sendText(String text) async {
    if (_sending || _thinking) return;

    final existingMessageIds = _messages.map((message) => message.id).toSet();
    var newUserMessageCommitted = false;

    setState(() {
      _sending = true;
      _thinking = true;
      _pendingUserContent = text;
      _streamingAnswer = '';
      _streamingReasoning = '';
      _askError = null;
    });
    _scrollToLatest();

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final result = await sendAgentConversationMessage(
        context: context,
        backend: backend,
        sessionKey: sessionKey,
        conversationId: widget.conversation.id,
        message: text,
        runtimeConversationSender: widget.runtimeConversationSender,
        onReasoningDelta: (delta) {
          if (!mounted) return;
          setState(() => _streamingReasoning += delta);
          _scrollToLatest();
        },
        onAnswerDelta: (delta) {
          if (!mounted) return;
          setState(() {
            _streamingReasoning = '';
            _streamingAnswer += delta;
          });
          _scrollToLatest();
        },
      );
      if (!mounted) return;
      newUserMessageCommitted = result.userMessageCommitted;

      if (result.routeKind == AskAiRouteKind.cloudGateway) {
        syncEngine?.notifyExternalChange();
        await Future.wait<Object>([
          _loadMessages(),
          _loadTasks(),
          _loadMemoryPages(),
        ]);
        if (!mounted) return;
        setState(() {
          _runtimeApprovalItems = _validApprovalItems(
            result.approvalItems,
          );
          _pendingUserContent = null;
          _streamingAnswer = '';
          _streamingReasoning = '';
          _thinking = false;
        });
        _scrollToLatest();
        return;
      }

      if (isAgentEmbeddingsQuotaStreamError(result.streamError)) {
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
      if (result.streamError != null ||
          (!result.sawVisibleDelta && !hasNewAssistantMessage)) {
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
    } on AgentConversationSendException catch (error) {
      if (!mounted) return;
      _showAskFailure(newUserMessageCommitted: error.userMessageCommitted);
    } catch (_) {
      if (!mounted) return;
      _showAskFailure(newUserMessageCommitted: newUserMessageCommitted);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _onQuickCaptureChanged();
      }
    }
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

  void _scrollToLatest() {
    void scrollAfterFrame(int remainingAttempts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final bottomContext = _messageListBottomKey.currentContext;
        if (bottomContext != null) {
          unawaited(
            Scrollable.ensureVisible(
              bottomContext,
              alignment: 1,
              duration: Duration.zero,
            ),
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        if (remainingAttempts > 0) {
          WidgetsBinding.instance.scheduleFrame();
          scrollAfterFrame(remainingAttempts - 1);
        }
      });
    }

    scrollAfterFrame(6);
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

  List<Widget> _buildRuntimeApprovalCards(BuildContext context) {
    if (_runtimeApprovalItems.isEmpty) return const <Widget>[];
    return [
      for (final item in _runtimeApprovalItems)
        _buildRuntimeApprovalCard(context, item),
    ];
  }

  Widget _buildRuntimeApprovalCard(
    BuildContext context,
    SecretaryRuntimeApprovalItem item,
  ) {
    final onApprove = _busyApprovalIds.contains(item.id)
        ? null
        : () => unawaited(_resolveRuntimeApproval(item, approve: true));
    final onReject = _busyApprovalIds.contains(item.id)
        ? null
        : () => unawaited(_resolveRuntimeApproval(item, approve: false));
    if (item.kind == 'task_mutation_confirmation') {
      return ApprovalPreviewCard(
        change: _runtimeApprovalPreviewChange(context, item),
        onApprove: onApprove,
        onReject: onReject,
      );
    }
    if (item.kind == 'memory_confirmation') {
      return _RuntimeMemoryCandidateCard(
        item: item,
        onApprove: onApprove,
        onReject: onReject,
      );
    }
    return _RuntimeCandidateApprovalCard(
      item: item,
      onApprove: onApprove,
      onReject: onReject,
      onEditTitle: _canEditRuntimeApprovalTitle(item) &&
              !_busyApprovalIds.contains(item.id)
          ? (title) => unawaited(_patchRuntimeApprovalTitle(item, title))
          : null,
    );
  }

  bool _canEditRuntimeApprovalTitle(SecretaryRuntimeApprovalItem item) {
    return item.kind == 'recurring_reminder_confirmation' &&
        item.editableFields.contains('title');
  }

  ApprovalPreviewChange _runtimeApprovalPreviewChange(
    BuildContext context,
    SecretaryRuntimeApprovalItem item,
  ) {
    final record = item.record ?? const <String, Object?>{};
    final todo = _todoById(item.taskId);
    final dueAfter = _runtimeDueAtMs(record);
    final reason = item.reason.trim();
    final sourceSentence = reason.isNotEmpty ? reason : item.title;
    return ApprovalPreviewChange(
      sourceSentence: sourceSentence,
      dueTimeBefore: todo == null
          ? context.t.chat.agentTasks.notScheduled
          : agentTaskSubtitle(todo),
      dueTimeAfter: agentTaskDueLabelFromMs(dueAfter),
      statusLabel: todo == null
          ? context.t.chat.agentTasks.statusOpen
          : agentTaskStatusLabel(todo),
    );
  }

  Todo? _todoById(String todoId) {
    final id = todoId.trim();
    if (id.isEmpty) return null;
    for (final todo in _todos) {
      if (todo.id == id) return todo;
    }
    return null;
  }

  Future<void> _resolveRuntimeApproval(
    SecretaryRuntimeApprovalItem item, {
    required bool approve,
  }) async {
    if (_busyApprovalIds.contains(item.id)) return;
    setState(() => _busyApprovalIds.add(item.id));

    try {
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final vaultId = cloudAuthScope?.controller.uid?.trim() ?? '';
      if (cloudAuthScope == null || vaultId.isEmpty) {
        throw StateError('managed_pro_vault_id_required');
      }
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final sender = widget.runtimeConversationSender ??
          SecretaryRuntimeConversationSender.hostedManagedPro(
            apiBaseUrl: cloudAuthScope.gatewayConfig.baseUrl,
            hostedSessionTokenGetter: cloudAuthScope.controller.getIdToken,
          );
      final service = RuntimeSecretaryAppService(
        sender: sender,
        backend: backend,
        sessionKey: sessionKey,
      );
      if (approve) {
        await service.approveApprovalItem(
          item,
          vaultId: vaultId,
          conversationId: widget.conversation.id,
          sourceMessageId: item.id,
        );
      } else {
        await service.rejectApprovalItem(
          item,
          vaultId: vaultId,
          conversationId: widget.conversation.id,
          sourceMessageId: item.id,
        );
      }
      if (!mounted) return;

      SyncEngineScope.maybeOf(context)?.notifyExternalChange();
      await Future.wait<Object>([
        _loadMessages(),
        _loadTasks(),
        _loadMemoryPages(),
      ]);
      if (!mounted) return;
      setState(() {
        _runtimeApprovalItems = _runtimeApprovalItems
            .where((candidate) => candidate.id != item.id)
            .toList(growable: false);
        _askError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _askError = context.t.chat.askAiFailedTemporary);
    } finally {
      if (mounted) {
        setState(() => _busyApprovalIds.remove(item.id));
      }
    }
  }

  Future<void> _patchRuntimeApprovalTitle(
    SecretaryRuntimeApprovalItem item,
    String title,
  ) async {
    final nextTitle = title.trim();
    if (nextTitle.isEmpty || _busyApprovalIds.contains(item.id)) return;
    setState(() => _busyApprovalIds.add(item.id));

    try {
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final vaultId = cloudAuthScope?.controller.uid?.trim() ?? '';
      if (cloudAuthScope == null || vaultId.isEmpty) {
        throw StateError('managed_pro_vault_id_required');
      }
      final sender = widget.runtimeConversationSender ??
          SecretaryRuntimeConversationSender.hostedManagedPro(
            apiBaseUrl: cloudAuthScope.gatewayConfig.baseUrl,
            hostedSessionTokenGetter: cloudAuthScope.controller.getIdToken,
          );
      final service = RuntimeSecretaryAppService(
        sender: sender,
        backend: AppBackendScope.of(context),
        sessionKey: SessionScope.of(context).sessionKey,
      );
      final updated = await service.patchApprovalItem(
        item,
        vaultId: vaultId,
        changes: <String, Object?>{'title': nextTitle},
      );
      if (!mounted) return;
      setState(() {
        _runtimeApprovalItems = [
          for (final candidate in _runtimeApprovalItems)
            candidate.id == updated.id ? updated : candidate,
        ];
        _askError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _askError = context.t.chat.askAiFailedTemporary);
    } finally {
      if (mounted) {
        setState(() => _busyApprovalIds.remove(item.id));
      }
    }
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
    final acceptanceCards = <Widget>[
      ..._buildAcceptanceCards(acceptanceController),
      ..._buildRuntimeApprovalCards(context),
    ];
    final contextSnapshot = acceptanceController?.contextSnapshot ??
        agentTaskContextSnapshot(_todos, memories: _memoryPages);
    final openTasksCount = agentOpenTasks(_todos).length;

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
                      todos: _todos,
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
                          openTasksCount: openTasksCount,
                          onOpenTasks: openTasksCount == 0
                              ? null
                              : () => showAgentTasksSheet(
                                    context: context,
                                    todos: _todos,
                                  ),
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
    required List<Todo> todos,
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
                  bottomKey: _messageListBottomKey,
                  messages: _messages,
                  todos: todos,
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

List<SecretaryRuntimeApprovalItem> _validApprovalItems(
  List<SecretaryRuntimeApprovalItem> items,
) {
  return items
      .where((item) => item.id.trim().isNotEmpty)
      .toList(growable: false);
}

int? _runtimeDueAtMs(Map<String, Object?> record) {
  return _runtimeInt(record['due_at_ms']) ??
      _runtimeInt(record['dueAtMs']) ??
      _runtimeInt(record['new_due_at_ms']) ??
      _runtimeInt(record['newDueAtMs']) ??
      _runtimeIsoDateTimeMs(record['due_local_iso']) ??
      _runtimeIsoDateTimeMs(record['dueLocalIso']) ??
      _runtimeTodayTimeMs(record['due_time']) ??
      _runtimeTodayTimeMs(record['dueTime']) ??
      _runtimeTodayTimeMs(record['new_due_time']) ??
      _runtimeTodayTimeMs(record['newDueTime']);
}

int? _runtimeIsoDateTimeMs(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;
  return DateTime.tryParse(value)?.millisecondsSinceEpoch;
}

int? _runtimeTodayTimeMs(Object? raw) {
  if (raw is! String) return null;
  final match =
      RegExp(r'([01]?\d|2[0-3])\s*[:：]\s*([0-5]\d)').firstMatch(raw.trim());
  if (match == null) return null;
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
  ).millisecondsSinceEpoch;
}

int? _runtimeInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}
