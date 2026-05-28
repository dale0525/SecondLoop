import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/secretary_backend.dart';
import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/runtime_agent_state_repository.dart';
import '../../core/cloud/runtime_connection_store.dart';
import '../../core/cloud/runtime_profile.dart';
import '../../core/cloud/runtime_secretary_app_service.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/secretary_runtime_client.dart';
import '../../core/cloud/secretary_runtime_conversation_sender.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/quick_capture/quick_capture_controller.dart';
import '../../core/quick_capture/quick_capture_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../app/app_shell_style.dart';
import '../../app/theme.dart';
import '../../i18n/strings.g.dart';
import 'package:secondloop/core/models/app_models.dart';
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
import '../attachments/attachment_draft_builders.dart';
import '../attachments/attachment_draft_send_contract.dart';
import '../attachments/attachment_viewer_page.dart';
import '../conversation_cards/approval_preview_card.dart';
import '../conversation_cards/calendar_event_approval_card.dart';
import '../conversation_cards/calendar_email_card.dart';
import '../conversation_cards/daily_brief_card.dart';
import '../conversation_cards/media_summary_card.dart';
import '../conversation_cards/research_brief_card.dart';
import '../conversation_cards/task_mutation_approval_card.dart';
import '../conversation_context/conversation_context_rail.dart';
import '../chat/chat_answer_citation_controller.dart';
import '../chat/chat_answer_evidence_models.dart';
import '../chat/chat_answer_evidence_parser.dart';
import '../chat/chat_assistant_message_footer.dart';
import '../chat/chat_markdown_link_handler.dart';
import '../chat/chat_markdown_preview.dart';
import '../chat/message_deeplink.dart';
import '../chat/message_viewer_page.dart';
import 'agent_design_tokens.dart';
import 'agent_conversation_send.dart';
import 'agent_status_chip.dart';
import 'agent_operating_system_tokens.dart';
import 'agent_task_summary.dart';
import 'agent_ui_acceptance_driver.dart';

part 'agent_assistant_text_message.dart';
part 'agent_conversation_attachments.dart';
part 'agent_conversation_attachment_widgets.dart';
part 'agent_conversation_runtime_pagination.dart';
part 'agent_conversation_runtime_connection.dart';
part 'agent_conversation_runtime_helpers.dart';
part 'agent_operating_top_app_bar.dart';
part 'agent_runtime_media_results.dart';
part 'agent_runtime_media_result_widgets.dart';
part 'agent_conversation_layouts.dart';
part 'agent_operating_approval_preview.dart';
part 'agent_desktop_workbench_layout.dart';
part 'agent_desktop_workbench_primitives.dart';
part 'agent_operating_research_cards.dart';
part 'agent_operating_reminder_cards.dart';
part 'agent_operating_action_candidate_cards.dart';
part 'agent_operating_email_cards.dart';
part 'agent_operating_safety_cards.dart';
part 'agent_operating_local_computer_safety_cards.dart';
part 'agent_operating_message_bubbles.dart';
part 'agent_operating_system_cards.dart';
part 'agent_conversation_widgets.dart';

final class AgentConversationPage extends StatefulWidget {
  const AgentConversationPage({
    required this.conversation,
    required this.isTabActive,
    this.runtimeConversationSender,
    this.runtimeAgentStateRepository,
    super.key,
  });

  final Conversation conversation;
  final bool isTabActive;
  final ChatRuntimeConversationSender? runtimeConversationSender;
  final RuntimeAgentStateRepository? runtimeAgentStateRepository;

  @override
  State<AgentConversationPage> createState() => _AgentConversationPageState();
}

final class _AgentConversationPageState extends State<AgentConversationPage>
    with _AgentConversationRuntimePagination {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _messageListBottomKey = GlobalKey();
  Future<List<Message>>? _messagesFuture;
  Future<List<Todo>>? _tasksFuture;
  Future<List<MemoryPageRecord>>? _memoryPagesFuture;
  Future<RuntimeAgentState>? _runtimeAgentStateFuture;
  Future<CloudRuntimeConnection?>? _runtimeConnectionLoadFuture;
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;
  QuickCaptureController? _quickCaptureController;
  List<Message> _messages = const <Message>[];
  List<Todo> _todos = const <Todo>[];
  List<MemoryPageRecord> _memoryPages = const <MemoryPageRecord>[];
  RuntimeAgentState? _runtimeAgentState;
  RuntimeConversationTurnPage _conversationTurnPage =
      RuntimeConversationTurnPage.empty;
  String? _pendingUserContent;
  List<_AgentMessageAttachmentView> _pendingUserAttachments =
      const <_AgentMessageAttachmentView>[];
  List<AttachmentDraftPayload> _pendingAttachmentDrafts =
      const <AttachmentDraftPayload>[];
  Map<String, List<_AgentMessageAttachmentView>> _messageAttachmentsById =
      const <String, List<_AgentMessageAttachmentView>>{};
  Map<String, List<_AgentMessageMediaResultView>> _messageMediaResultsById =
      const <String, List<_AgentMessageMediaResultView>>{};
  Map<String, _AgentMessageAttachmentView> _sentAttachmentsByRef =
      const <String, _AgentMessageAttachmentView>{};
  String _streamingAnswer = '';
  String _streamingReasoning = '';
  String? _askError;
  int _attachmentDraftSeq = 0;
  List<SecretaryRuntimeApprovalItem> _runtimeApprovalItems =
      const <SecretaryRuntimeApprovalItem>[];
  final Set<String> _busyApprovalIds = <String>{};
  bool _sending = false;
  bool _thinking = false;
  bool _loadingOlderRuntimeTurns = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureRuntimeConnectionLoaded();
    if (_usesRuntimeAgentState) {
      _runtimeAgentStateFuture ??= _loadRuntimeAgentState();
      _messagesFuture =
          _runtimeAgentStateFuture!.then((_) => List<Message>.from(_messages));
    } else {
      _messagesFuture ??= _loadMessages();
      _tasksFuture ??= _loadTasks();
      _memoryPagesFuture ??= _loadMemoryPages();
    }
    _attachSyncEngine();
    _attachQuickCaptureController();
  }

  void _activateRuntimeStateAfterConnectionLoad() {
    setState(() {
      _runtimeAgentStateFuture = _loadRuntimeAgentState();
      _messagesFuture =
          _runtimeAgentStateFuture!.then((_) => List<Message>.from(_messages));
    });
  }

  void _rebuildAfterRuntimeConnectionLoad() {
    setState(() {});
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

  Future<RuntimeAgentState> _loadRuntimeAgentState({
    String? turnBefore,
    bool prependOlderTurns = false,
  }) async {
    final vaultId = _activeRuntimeVaultId();
    final repository = _runtimeStateRepository();
    if (repository == null || vaultId.isEmpty) {
      return RuntimeAgentState.empty(
        vaultId: vaultId,
        conversationId: widget.conversation.id,
      );
    }
    late final RuntimeAgentState state;
    try {
      state = await _fetchRuntimeAgentStatePage(
        repository,
        vaultId: vaultId,
        conversationId: widget.conversation.id,
        turnBefore: turnBefore,
      );
    } catch (_) {
      state = RuntimeAgentState.empty(
        vaultId: vaultId,
        conversationId: widget.conversation.id,
      );
      if (mounted) {
        setState(() {
          _runtimeAgentState = state;
          _conversationTurnPage = RuntimeConversationTurnPage.empty;
          _messages = const <Message>[];
          _todos = const <Todo>[];
          _memoryPages = const <MemoryPageRecord>[];
          _runtimeApprovalItems = const <SecretaryRuntimeApprovalItem>[];
          _messageAttachmentsById =
              const <String, List<_AgentMessageAttachmentView>>{};
          _messageMediaResultsById =
              const <String, List<_AgentMessageMediaResultView>>{};
        });
      }
      return state;
    }
    if (mounted) {
      final projection = _runtimeMessagesFromTurns(
        state.conversationTurns,
        localAttachmentsByRef: _sentAttachmentsByRef,
        mediaRecords: _runtimeMediaResultRecordsForState(state),
        mediaLabels: _runtimeMediaInlineLabels(context),
      );
      final attachmentsByMessageId = await _hydrateRuntimeAttachmentBytes(
        projection.attachmentsByMessageId,
        vaultId: vaultId,
      );
      if (!mounted) return state;
      setState(() {
        _runtimeAgentState = state;
        _conversationTurnPage = state.conversationTurnPage;
        if (prependOlderTurns) {
          final existingMessageIds =
              _messages.map((message) => message.id).toSet();
          _messages = <Message>[
            ...projection.messages.where(
              (message) => existingMessageIds.add(message.id),
            ),
            ..._messages,
          ];
          _messageAttachmentsById = <String, List<_AgentMessageAttachmentView>>{
            ...attachmentsByMessageId,
            ..._messageAttachmentsById,
          };
          _messageMediaResultsById =
              <String, List<_AgentMessageMediaResultView>>{
            ...projection.mediaResultsByMessageId,
            ..._messageMediaResultsById,
          };
        } else {
          _messages = projection.messages;
          _messageAttachmentsById = attachmentsByMessageId;
          _messageMediaResultsById = projection.mediaResultsByMessageId;
        }
        _todos = agentTodosFromRuntimeState(state);
        _memoryPages = agentMemoryPagesFromRuntimeState(state);
        _runtimeApprovalItems = _validApprovalItems(
          state.approvalItems
              .map(
                (item) => SecretaryRuntimeApprovalItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false),
        );
      });
      if (!prependOlderTurns) {
        _scrollToLatest();
      }
    }
    return state;
  }

  Future<void> _refreshVisibleState() async {
    if (_usesRuntimeAgentState) {
      final future = _loadRuntimeAgentState();
      _runtimeAgentStateFuture = future;
      await future;
      _messagesFuture = Future<List<Message>>.value(
        List<Message>.from(_messages),
      );
      return;
    }
    await Future.wait<Object>([
      _loadMessages(),
      _loadTasks(),
      _loadMemoryPages(),
    ]);
  }

  Future<List<Todo>> _loadTasks() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final todos = await backend.listTodos(sessionKey);
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
    final pages = await secretaryBackend.listMemoryPages(
      sessionKey,
      state: 'active',
    );
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
        if (_usesRuntimeAgentState) {
          _runtimeAgentStateFuture = _loadRuntimeAgentState();
          _messagesFuture = _runtimeAgentStateFuture!
              .then((_) => List<Message>.from(_messages));
        } else {
          _messagesFuture = _loadMessages();
          _tasksFuture = _loadTasks();
          _memoryPagesFuture = _loadMemoryPages();
        }
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

  String _nextAttachmentLocalId() {
    _attachmentDraftSeq += 1;
    return 'agent_attachment_$_attachmentDraftSeq';
  }

  Future<void> _pickAttachments() async {
    if (_sending || _thinking) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    final drafts = <AttachmentDraftPayload>[];
    for (final file in result.files) {
      final bytes = await _readPickedFileBytes(file);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) continue;
      drafts.add(
        buildAttachmentDraftPayload(
          localId: _nextAttachmentLocalId(),
          filename: file.name,
          mimeType: inferAttachmentMimeTypeFromFilename(file.name),
          rawBytes: bytes,
        ),
      );
    }
    if (drafts.isEmpty) return;

    setState(() {
      _pendingAttachmentDrafts = dedupeAttachmentDraftPayloads([
        ..._pendingAttachmentDrafts,
        ...drafts,
      ]);
      _askError = null;
    });
    _focusNode.requestFocus();
  }

  Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null) return bytes;
    try {
      return await file.xFile.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  void _removePendingAttachment(String localId) {
    setState(() {
      _pendingAttachmentDrafts = _pendingAttachmentDrafts
          .where((draft) => draft.localId != localId)
          .toList(growable: false);
    });
  }

  Future<void> _send() async {
    if (_sending || _thinking) return;

    final text = _controller.text.trim();
    final attachments = List<AttachmentDraftPayload>.from(
      _pendingAttachmentDrafts,
    );
    if (text.isEmpty && attachments.isEmpty) return;
    _controller.clear();
    if (attachments.isNotEmpty) {
      setState(
          () => _pendingAttachmentDrafts = const <AttachmentDraftPayload>[]);
    }
    await _sendText(text, attachments: attachments);
  }

  Future<void> _sendText(
    String text, {
    List<AttachmentDraftPayload> attachments = const <AttachmentDraftPayload>[],
  }) async {
    if (_sending || _thinking) return;

    final normalizedText = text.trim();
    final dedupedAttachments = dedupeAttachmentDraftPayloads(attachments);
    if (normalizedText.isEmpty && dedupedAttachments.isEmpty) return;
    final messageText = normalizedText.isEmpty
        ? _attachmentOnlyFallbackText(dedupedAttachments)
        : normalizedText;
    final attachmentIntent =
        _runtimeAttachmentIntent(normalizedText, dedupedAttachments);
    final runtimeAttachments =
        await _runtimeAttachmentPayloads(dedupedAttachments);
    final messageAttachments =
        _runtimeMessageAttachmentPayloads(runtimeAttachments);
    if (!mounted) return;
    final outgoingAttachmentViews =
        _messageAttachmentsFromRuntimePayloads(runtimeAttachments);
    var newUserMessageCommitted = false;

    setState(() {
      _sending = true;
      _thinking = true;
      _pendingUserContent = messageText;
      _pendingUserAttachments = outgoingAttachmentViews;
      _sentAttachmentsByRef = {
        ..._sentAttachmentsByRef,
        for (final attachment in outgoingAttachmentViews)
          attachment.id: attachment,
      };
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
        message: normalizedText,
        attachments: messageAttachments,
        uploadAttachments: runtimeAttachments,
        messageDisplayText: attachmentIntent == null ? null : messageText,
        attachmentIntent: attachmentIntent,
        runtimeConversationSender: widget.runtimeConversationSender,
      );
      if (!mounted) return;
      newUserMessageCommitted = result.userMessageCommitted;

      if (result.routeKind == AskAiRouteKind.cloudGateway) {
        syncEngine?.notifyExternalChange();
        try {
          await _refreshVisibleState();
        } catch (_) {
          if (!mounted) return;
          _showRuntimeSendFallback(
            userContent: messageText,
            userAttachments: outgoingAttachmentViews,
            result: result,
          );
          _scrollToLatest();
          return;
        }
        if (!mounted) return;
        if (result.sawVisibleDelta &&
            !_hasVisibleRuntimeAssistantContent(result.assistantContent)) {
          _showRuntimeSendFallback(
            userContent: messageText,
            userAttachments: outgoingAttachmentViews,
            result: result,
          );
          _scrollToLatest();
          return;
        }
        setState(() {
          _applyRuntimeResultMediaFallback(result);
          _runtimeApprovalItems = _validApprovalItems(
            _runtimeApprovalItems.isEmpty
                ? result.approvalItems
                : _runtimeApprovalItems,
          );
          _pendingUserContent = null;
          _pendingUserAttachments = const <_AgentMessageAttachmentView>[];
          _streamingAnswer = '';
          _streamingReasoning = '';
          _thinking = false;
        });
        _scrollToLatest();
        return;
      }

      _showAskFailure(newUserMessageCommitted: newUserMessageCommitted);
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
        _pendingUserAttachments = const <_AgentMessageAttachmentView>[];
      }
    });
  }

  void _updateRuntimeState(VoidCallback update) {
    setState(update);
  }

  bool _hasVisibleRuntimeAssistantContent(String content) {
    final normalized = content.trim();
    if (normalized.isEmpty) return true;
    return _messages.any(
      (message) =>
          message.role == 'assistant' && message.content.trim() == normalized,
    );
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
    if (_isOperatingActionItemCandidate(item)) {
      return _OperatingActionItemCandidateCard(
        item: item,
        onCreate: onApprove,
        onDismiss: onReject,
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
      final vaultId = _activeRuntimeVaultId();
      if (vaultId.isEmpty) throw StateError('runtime_vault_id_required');
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final sender = _runtimeConversationSender();
      if (sender == null) throw StateError('runtime_sender_required');
      final service = RuntimeSecretaryAppService(
        sender: sender,
        backend: backend,
        sessionKey: sessionKey,
      );
      final approvalCountBeforeDecision = _runtimeApprovalItems.length;
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
      await _refreshVisibleState();
      if (!mounted) return;
      List<SecretaryRuntimeApprovalItem>? refreshedApprovalItems;
      try {
        final fetchedApprovalItems = _validApprovalItems(
          await service.fetchApprovalItems(vaultId: vaultId),
        );
        if (fetchedApprovalItems.isNotEmpty ||
            approvalCountBeforeDecision <= 1 ||
            _runtimeApprovalItems.length <= 1) {
          refreshedApprovalItems = fetchedApprovalItems;
        }
      } catch (_) {
        refreshedApprovalItems = null;
      }
      setState(() {
        final currentApprovalItems =
            refreshedApprovalItems ?? _runtimeApprovalItems;
        _runtimeApprovalItems = currentApprovalItems
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
      final vaultId = _activeRuntimeVaultId();
      if (vaultId.isEmpty) throw StateError('runtime_vault_id_required');
      final sender = _runtimeConversationSender();
      if (sender == null) throw StateError('runtime_sender_required');
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
    final parentTheme = Theme.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final theme = parentTheme.brightness == Brightness.dark
        ? AppTheme.dark(locale: locale, platform: parentTheme.platform)
        : AppTheme.light(locale: locale, platform: parentTheme.platform);
    final colors = AgentOperatingSystemTokens.of(context);
    final acceptanceController = AgentUiAcceptanceScope.maybeOf(context);
    final acceptanceCards = _buildAcceptanceCards(acceptanceController);
    final runtimeApprovalCards = _buildRuntimeApprovalCards(context);
    final mobileAcceptanceCards = <Widget>[
      ...acceptanceCards,
      ...runtimeApprovalCards,
    ];
    final runtimeAgentState = _runtimeAgentState;
    final contextSnapshot = acceptanceController?.contextSnapshot ??
        (runtimeAgentState == null
            ? agentTaskContextSnapshot(_todos, memories: _memoryPages)
            : agentRuntimeContextSnapshot(runtimeAgentState));
    final openTasksCount = agentOpenTasks(_todos).length;

    return Theme(
      data: theme,
      child: Material(
        color: colors.background,
        child: ColoredBox(
          key: const ValueKey('agent_conversation_workspace'),
          color: colors.background,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shellDesktopWorkbench =
                  AppShellLayoutScope.desktopWorkbenchOf(context);
              final useDesktopWorkbench =
                  shellDesktopWorkbench ?? (constraints.maxWidth >= 960);
              if (!useDesktopWorkbench) {
                return _buildOperatingSystemMobileShell(
                  context,
                  acceptanceCards: mobileAcceptanceCards,
                  todos: _todos,
                );
              }
              final desktopAcceptanceCards = runtimeAgentState == null
                  ? mobileAcceptanceCards
                  : acceptanceCards;
              return _buildOperatingSystemDesktopWorkbench(
                context,
                acceptanceCards: desktopAcceptanceCards,
                todos: _todos,
                contextSnapshot: contextSnapshot,
                openTasksCount: openTasksCount,
              );
            },
          ),
        ),
      ),
    );
  }
}
