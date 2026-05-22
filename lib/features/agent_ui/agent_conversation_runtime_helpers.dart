part of 'agent_conversation_page.dart';

extension _AgentConversationRuntimeHelpers on _AgentConversationPageState {
  void _showRuntimeSendFallback({
    required String userContent,
    required List<_AgentMessageAttachmentView> userAttachments,
    required AgentConversationSendResult result,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final userMessageId = 'runtime_local_user_$nowMs';
    final assistantMessageId = 'runtime_local_assistant_$nowMs';
    final assistantContent = result.assistantContent.trim();
    final fallbackMediaResults = _agentMessageMediaResultViewsFromRaw(
      result.mediaResults,
      labels: _runtimeMediaInlineLabels(context),
    );
    final nextMessages = <Message>[
      ..._messages,
      Message(
        id: userMessageId,
        conversationId: widget.conversation.id,
        role: 'user',
        content: userContent,
        createdAtMs: nowMs,
        isMemory: true,
      ),
      if (assistantContent.isNotEmpty)
        Message(
          id: assistantMessageId,
          conversationId: widget.conversation.id,
          role: 'assistant',
          content: assistantContent,
          createdAtMs: nowMs + 1,
          isMemory: true,
        ),
    ];

    _updateRuntimeState(() {
      _messages = nextMessages;
      _messagesFuture = Future<List<Message>>.value(nextMessages);
      if (_usesRuntimeAgentState) {
        _runtimeAgentStateFuture = Future<RuntimeAgentState>.value(
          _runtimeAgentState ??
              RuntimeAgentState.empty(
                vaultId:
                    CloudAuthScope.maybeOf(context)?.controller.uid?.trim() ??
                        '',
                conversationId: widget.conversation.id,
              ),
        );
      }
      if (userAttachments.isNotEmpty) {
        _messageAttachmentsById =
            Map<String, List<_AgentMessageAttachmentView>>.unmodifiable({
          ..._messageAttachmentsById,
          userMessageId:
              List<_AgentMessageAttachmentView>.unmodifiable(userAttachments),
        });
      }
      if (fallbackMediaResults.isNotEmpty && assistantContent.isNotEmpty) {
        _messageMediaResultsById =
            Map<String, List<_AgentMessageMediaResultView>>.unmodifiable({
          ..._messageMediaResultsById,
          assistantMessageId: List<_AgentMessageMediaResultView>.unmodifiable(
            fallbackMediaResults,
          ),
        });
      }
      _runtimeApprovalItems = _validApprovalItems(
        result.approvalItems.isEmpty
            ? _runtimeApprovalItems
            : result.approvalItems,
      );
      _pendingUserContent = null;
      _pendingUserAttachments = const <_AgentMessageAttachmentView>[];
      _streamingAnswer = '';
      _streamingReasoning = '';
      _askError = null;
      _thinking = false;
    });
  }

  void _applyRuntimeResultMediaFallback(AgentConversationSendResult result) {
    final fallbackMediaResults = _agentMessageMediaResultViewsFromRaw(
      result.mediaResults,
      labels: _runtimeMediaInlineLabels(context),
    );
    if (fallbackMediaResults.isEmpty) return;

    final assistantMessageId = _assistantMessageIdForRuntimeResult(
      result.turnId,
      _messages,
    );
    if (assistantMessageId == null) return;

    final existing = _messageMediaResultsById[assistantMessageId];
    if (existing != null && existing.isNotEmpty) return;

    _messageMediaResultsById =
        Map<String, List<_AgentMessageMediaResultView>>.unmodifiable({
      ..._messageMediaResultsById,
      assistantMessageId: List<_AgentMessageMediaResultView>.unmodifiable(
        fallbackMediaResults,
      ),
    });
  }
}

String? _assistantMessageIdForRuntimeResult(
  String turnId,
  List<Message> messages,
) {
  final normalizedTurnId = turnId.trim();
  if (normalizedTurnId.isNotEmpty) {
    for (final message in messages) {
      if (message.id == normalizedTurnId && message.role == 'assistant') {
        return message.id;
      }
    }
  }

  for (final message in messages.reversed) {
    if (message.role == 'assistant') return message.id;
  }
  return null;
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
