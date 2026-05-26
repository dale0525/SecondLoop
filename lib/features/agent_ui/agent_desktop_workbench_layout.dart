part of 'agent_conversation_page.dart';

extension _AgentDesktopWorkbenchLayout on _AgentConversationPageState {
  Widget _buildOperatingSystemDesktopWorkbench(
    BuildContext context, {
    required List<Widget> acceptanceCards,
    required List<Todo> todos,
    required ConversationContextSnapshot contextSnapshot,
    required int openTasksCount,
  }) {
    final state = _runtimeAgentState;
    final sidePanelApprovalItems = state == null
        ? const <SecretaryRuntimeApprovalItem>[]
        : _runtimeApprovalItems;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 7,
          child: _DesktopWorkbenchChatColumn(
            messages: _messages,
            runtimeState: state,
            taskRecords: state?.tasks ?? const <RuntimeWorkingSetRecord>[],
            todos: todos,
            acceptanceCards: acceptanceCards,
            pendingUserContent: _pendingUserContent,
            pendingUserAttachments: _pendingUserAttachments,
            messageAttachmentsById: _messageAttachmentsById,
            messageMediaResultsById: _messageMediaResultsById,
            streamingAnswer: _streamingAnswer,
            thinking: _thinking,
            askError: _askError,
            hasMoreBefore: _conversationTurnPage.hasMoreBefore,
            loadingOlderTurns: _loadingOlderRuntimeTurns,
            scrollController: _scrollController,
            bottomKey: _messageListBottomKey,
            controller: _controller,
            focusNode: _focusNode,
            busy: _sending || _thinking,
            attachments: _pendingAttachmentDrafts,
            onAttach: () => unawaited(_pickAttachments()),
            onRemoveAttachment: _removePendingAttachment,
            onSend: _send,
            onLoadOlderTurns: _loadOlderRuntimeTurns,
            onTaskViewed: _recordTaskFocus,
          ),
        ),
        const VerticalDivider(
          width: 1,
          color: AgentOperatingSystemTokens.outlineVariant,
        ),
        Expanded(
          flex: 5,
          child: _DesktopWorkbenchSidePanels(
            state: state,
            approvalItems: sidePanelApprovalItems,
            contextSnapshot: contextSnapshot,
            openTasksCount: openTasksCount,
            onApprove: (item) => unawaited(
              _resolveRuntimeApproval(item, approve: true),
            ),
            onReject: (item) => unawaited(
              _resolveRuntimeApproval(item, approve: false),
            ),
          ),
        ),
      ],
    );
  }
}

final class _DesktopWorkbenchChatColumn extends StatelessWidget {
  const _DesktopWorkbenchChatColumn({
    required this.messages,
    required this.runtimeState,
    required this.taskRecords,
    required this.todos,
    required this.acceptanceCards,
    required this.pendingUserContent,
    required this.pendingUserAttachments,
    required this.messageAttachmentsById,
    required this.messageMediaResultsById,
    required this.streamingAnswer,
    required this.thinking,
    required this.askError,
    required this.hasMoreBefore,
    required this.loadingOlderTurns,
    required this.scrollController,
    required this.bottomKey,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.attachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onLoadOlderTurns,
    required this.onTaskViewed,
  });

  final List<Message> messages;
  final RuntimeAgentState? runtimeState;
  final List<RuntimeWorkingSetRecord> taskRecords;
  final List<Todo> todos;
  final List<Widget> acceptanceCards;
  final String? pendingUserContent;
  final List<_AgentMessageAttachmentView> pendingUserAttachments;
  final Map<String, List<_AgentMessageAttachmentView>> messageAttachmentsById;
  final Map<String, List<_AgentMessageMediaResultView>> messageMediaResultsById;
  final String streamingAnswer;
  final bool thinking;
  final String? askError;
  final bool hasMoreBefore;
  final bool loadingOlderTurns;
  final ScrollController scrollController;
  final Key bottomKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final List<AttachmentDraftPayload> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;
  final Future<void> Function() onLoadOlderTurns;
  final ValueChanged<Todo> onTaskViewed;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? sourceUserMessageId;
    var renderedWebResearch = false;
    final turnsById = <String, RuntimeConversationTurn>{
      for (final turn in runtimeState?.conversationTurns ??
          const <RuntimeConversationTurn>[])
        if (turn.turnId.trim().isNotEmpty) turn.turnId: turn,
    };
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      if (message.role == 'assistant') {
        final runtimeTurn = turnsById[message.id];
        final isWebResearch =
            _isOperatingWebResearchMessage(message, runtimeTurn);
        children.add(
          isWebResearch
              ? _OperatingAssistantResponse(
                  message: message,
                  runtimeTurn: runtimeTurn,
                  contextSnapshot: runtimeState?.latestContextSnapshot,
                  isFollowUpResearch: renderedWebResearch,
                  mediaResults: messageMediaResultsById[message.id] ??
                      const <_AgentMessageMediaResultView>[],
                )
              : _DesktopAssistantTurn(
                  message: message,
                  createdTasks: _createdTasks(sourceUserMessageId, message.id),
                  mediaResults: messageMediaResultsById[message.id] ??
                      const <_AgentMessageMediaResultView>[],
                  onTaskViewed: onTaskViewed,
                ),
        );
        if (isWebResearch) {
          renderedWebResearch = true;
        }
        sourceUserMessageId = null;
      } else {
        children.add(
          _DesktopUserTurn(
            content: message.content,
            attachments: messageAttachmentsById[message.id] ??
                const <_AgentMessageAttachmentView>[],
          ),
        );
        sourceUserMessageId = message.id;
      }
    }

    if (acceptanceCards.isNotEmpty) {
      children.add(_AcceptanceCardStack(cards: acceptanceCards));
    }

    final pendingText = pendingUserContent?.trim();
    if (pendingText != null && pendingText.isNotEmpty) {
      children.add(
        _DesktopUserTurn(
          content: pendingText,
          attachments: pendingUserAttachments,
        ),
      );
    }
    final streamed = streamingAnswer.trim();
    if (streamed.isNotEmpty) {
      children.add(
        _DesktopAssistantTurn(
          message: Message(
            id: 'streaming',
            conversationId: '',
            role: 'assistant',
            content: streamed,
            createdAtMs: 0,
            isMemory: true,
          ),
          createdTasks: const <Todo>[],
          mediaResults: const <_AgentMessageMediaResultView>[],
          onTaskViewed: onTaskViewed,
        ),
      );
    } else if (thinking) {
      children.add(const _DesktopToolStatus(label: 'runtime: processing'));
    }
    final error = askError?.trim();
    if (error != null && error.isNotEmpty) {
      children.add(_DesktopToolStatus(label: error));
    }

    if (children.isEmpty) {
      children.add(
        _EmptyState(
          title: context.t.chat.noMessagesYet,
          subtitle: context.t.chat.agentConversation.composerHint,
        ),
      );
    }
    children.add(SizedBox(key: bottomKey, height: 1));

    return ColoredBox(
      key: const ValueKey('desktop_workbench_chat_column'),
      color: AgentOperatingSystemTokens.background,
      child: Column(
        children: [
          if (hasMoreBefore)
            _LoadEarlierRuntimeTurnsButton(
              loading: loadingOlderTurns,
              onPressed: onLoadOlderTurns,
            ),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.all(32),
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(height: 32),
              itemBuilder: (context, index) => children[index],
            ),
          ),
          _DesktopComposer(
            controller: controller,
            focusNode: focusNode,
            busy: busy,
            attachments: attachments,
            onAttach: onAttach,
            onRemoveAttachment: onRemoveAttachment,
            onSend: onSend,
          ),
        ],
      ),
    );
  }

  List<Todo> _createdTasks(String? userMessageId, String assistantId) {
    final sourceIds = {
      assistantId.trim(),
      if (userMessageId?.trim().isNotEmpty ?? false) userMessageId!.trim(),
    }..remove('');
    final records = taskRecords.where((record) {
      final sourceId = _firstOperatingString([
        record.raw['source_message_id'],
        record.raw['sourceMessageId'],
        record.raw['source_entry_id'],
        record.raw['sourceEntryId'],
      ]);
      if (sourceId != null) return sourceIds.contains(sourceId);
      return _taskRecordHasRecentEntityRef(record, sourceIds);
    }).toList(growable: false);
    return [
      for (final record in records) agentTodoFromRuntimeTask(record),
    ];
  }

  bool _taskRecordHasRecentEntityRef(
    RuntimeWorkingSetRecord record,
    Set<String> sourceIds,
  ) {
    final recordId = record.id.trim();
    if (recordId.isEmpty || sourceIds.isEmpty) return false;
    final refs =
        runtimeState?.recentEntityRefs ?? const <Map<String, Object?>>[];
    return refs.any((ref) {
      final type = _firstOperatingString([
        ref['entity_type'],
        ref['entityType'],
        ref['kind'],
      ])?.toLowerCase();
      if (type != 'task') return false;
      final entityId = _firstOperatingString([
        ref['entity_id'],
        ref['entityId'],
        ref['record_id'],
        ref['recordId'],
        ref['id'],
      ]);
      if (entityId != recordId) return false;
      final sourceId = _firstOperatingString([
        ref['turn_id'],
        ref['turnId'],
        ref['source_turn_id'],
        ref['sourceTurnId'],
        ref['source_message_id'],
        ref['sourceMessageId'],
        ref['source_entry_id'],
        ref['sourceEntryId'],
        ref['source'],
      ]);
      return sourceId != null && sourceIds.contains(sourceId);
    });
  }
}

final class _DesktopUserTurn extends StatelessWidget {
  const _DesktopUserTurn({
    required this.content,
    required this.attachments,
  });

  final String content;
  final List<_AgentMessageAttachmentView> attachments;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surfaceContainerHigh,
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  content,
                  style: AgentOperatingSystemTokens.bodyMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                  ),
                ),
                if (attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MessageAttachmentStrip(attachments: attachments),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _DesktopAssistantTurn extends StatelessWidget {
  const _DesktopAssistantTurn({
    required this.message,
    required this.createdTasks,
    required this.mediaResults,
    required this.onTaskViewed,
  });

  final Message message;
  final List<Todo> createdTasks;
  final List<_AgentMessageMediaResultView> mediaResults;
  final ValueChanged<Todo> onTaskViewed;

  @override
  Widget build(BuildContext context) {
    return _AssistantTextMessage(
      content: message.content,
      time: context.t.chat.agentConversation.done,
      sourceMessage: message.id == 'streaming' ? null : message,
      createdTasks: createdTasks,
      mediaResults: mediaResults,
      onTaskViewed: (todo) async => onTaskViewed(todo),
    );
  }
}

final class _DesktopWorkbenchSidePanels extends StatelessWidget {
  const _DesktopWorkbenchSidePanels({
    required this.state,
    required this.approvalItems,
    required this.contextSnapshot,
    required this.openTasksCount,
    required this.onApprove,
    required this.onReject,
  });

  final RuntimeAgentState? state;
  final List<SecretaryRuntimeApprovalItem> approvalItems;
  final ConversationContextSnapshot contextSnapshot;
  final int openTasksCount;
  final ValueChanged<SecretaryRuntimeApprovalItem> onApprove;
  final ValueChanged<SecretaryRuntimeApprovalItem> onReject;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('desktop_workbench_side_panels'),
      color: AgentOperatingSystemTokens.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _DesktopPanel(
            title: 'Runtime Context',
            trailing: 'v4.11.0',
            child: _DesktopRuntimeContext(
              state: state,
              contextSnapshot: contextSnapshot,
              openTasksCount: openTasksCount,
            ),
          ),
          const SizedBox(height: 24),
          _DesktopPanel(
            title: 'Pending Approvals',
            count: approvalItems.length,
            child: approvalItems.isEmpty
                ? const Text('No pending approvals')
                : Column(
                    children: [
                      for (final item in approvalItems) ...[
                        _DesktopApprovalCard(
                          item: item,
                          onApprove: () => onApprove(item),
                          onReject: () => onReject(item),
                        ),
                        if (item != approvalItems.last)
                          const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          _DesktopPanel(
            title: 'Tool Trace',
            trailingIcon: Icons.history_rounded,
            child: _DesktopToolTrace(state: state),
          ),
        ],
      ),
    );
  }
}

final class _DesktopRuntimeContext extends StatelessWidget {
  const _DesktopRuntimeContext({
    required this.state,
    required this.contextSnapshot,
    required this.openTasksCount,
  });

  final RuntimeAgentState? state;
  final ConversationContextSnapshot contextSnapshot;
  final int openTasksCount;

  @override
  Widget build(BuildContext context) {
    final packet =
        state?.latestContextSnapshot?.packet ?? const <String, Object?>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: ConversationContextRail(
            snapshot: contextSnapshot,
            compact: true,
            openTasksCount: openTasksCount,
          ),
        ),
        const _DesktopPanelDivider(),
        _DesktopLabeledValue(
          label: 'recent_turns',
          value: _firstOperatingString([packet['recent_turns']]) ??
              _latestUserTurn(state) ??
              'none',
        ),
        const _DesktopPanelDivider(),
        _DesktopLabeledValue(
          label: 'Context Status',
          value: _firstOperatingString([packet['context_status']]) ??
              'context snapshot ready',
        ),
        const _DesktopPanelDivider(),
        _DesktopLabeledValue(
          label: 'Active Memory',
          value: _activeMemoryLabel(state, contextSnapshot),
          icon: Icons.translate_rounded,
        ),
      ],
    );
  }
}

final class _DesktopToolTrace extends StatelessWidget {
  const _DesktopToolTrace({required this.state});

  final RuntimeAgentState? state;

  @override
  Widget build(BuildContext context) {
    final trace = _latestToolTrace(state);
    final hasCitations = _latestAssistantHasCitations(state);
    final citationBadge = _desktopCitationBadgeLabel(
      trace: trace,
      hasCitations: hasCitations,
    );
    final traceFooter = _desktopToolTraceFooter(state, trace);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            color: AgentOperatingSystemTokens.secondary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _desktopToolTraceTitle(trace),
                      style: AgentOperatingSystemTokens.labelLg,
                    ),
                  ),
                  if (citationBadge != null)
                    _DesktopBadge(
                      label: citationBadge,
                      background: hasCitations
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFFF1F2),
                      foreground: hasCitations
                          ? const Color(0xFF059669)
                          : const Color(0xFFE11D48),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AgentOperatingSystemTokens.surface,
                  borderRadius: BorderRadius.circular(
                    AgentOperatingSystemTokens.radiusSm,
                  ),
                  border: Border.all(
                    color: AgentOperatingSystemTokens.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _DesktopTraceRow(
                        label: 'postprocess:',
                        value: _firstOperatingString([
                              trace['postprocess'],
                              trace['post_process'],
                            ]) ??
                            'not reported',
                      ),
                      const SizedBox(height: 8),
                      _DesktopTraceRow(
                        label: 'current facts:',
                        value: _firstOperatingString([
                              trace['current_facts'],
                              trace['currentFacts'],
                            ]) ??
                            (trace.isEmpty
                                ? 'tool_unavailable'
                                : 'not reported'),
                      ),
                    ],
                  ),
                ),
              ),
              if (traceFooter != null) ...[
                const SizedBox(height: 10),
                Text(
                  traceFooter,
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

final class _DesktopApprovalCard extends StatelessWidget {
  const _DesktopApprovalCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final SecretaryRuntimeApprovalItem item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final record = item.record ?? const <String, Object?>{};
    final taskTitle = _firstOperatingString([
          record['task_title'],
          record['taskTitle'],
          record['title'],
        ]) ??
        item.title;
    final before = _firstOperatingString([
          record['before'],
          record['old_title'],
          record['oldTitle'],
        ]) ??
        'previous value';
    final after = _firstOperatingString([
          record['after'],
          record['new_title'],
          record['newTitle'],
        ]) ??
        item.title;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: AgentOperatingSystemTokens.labelLg),
                const SizedBox(height: 4),
                Text(
                  "Change requested for '$taskTitle'",
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            color: AgentOperatingSystemTokens.outlineVariant,
          ),
          ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _DesktopDiffLine(
                    prefix: '-',
                    text: before,
                    color: const Color(0xFFE11D48),
                    background: const Color(0xFFFFF1F2),
                  ),
                  const SizedBox(height: 6),
                  _DesktopDiffLine(
                    prefix: '+',
                    text: after,
                    color: const Color(0xFF059669),
                    background: const Color(0xFFECFDF5),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onApprove,
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _DesktopComposer extends StatelessWidget {
  const _DesktopComposer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.attachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final List<AttachmentDraftPayload> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        border: Border(
          top: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 896),
            child: DecoratedBox(
              key: const ValueKey('desktop_workbench_composer_box'),
              decoration: BoxDecoration(
                color: AgentOperatingSystemTokens.surface,
                borderRadius:
                    BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
                border: Border.all(
                  color: AgentOperatingSystemTokens.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (attachments.isNotEmpty) ...[
                      _AttachmentDraftStrip(
                        attachments: attachments,
                        onRemoveAttachment: onRemoveAttachment,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        IconButton(
                          key: const ValueKey('chat_attach'),
                          tooltip: 'Attach',
                          onPressed: busy ? null : onAttach,
                          icon: const Icon(Icons.attach_file_rounded),
                        ),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('chat_input'),
                            controller: controller,
                            focusNode: focusNode,
                            minLines: 1,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Input instructions for the agent...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, child) {
                            final enabled = !busy &&
                                (value.text.trim().isNotEmpty ||
                                    attachments.isNotEmpty);
                            return SizedBox.square(
                              dimension: 40,
                              child: FilledButton(
                                key: const ValueKey('chat_send'),
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AgentOperatingSystemTokens.radiusSm,
                                    ),
                                  ),
                                ),
                                onPressed: enabled ? onSend : null,
                                child: const Icon(Icons.send_rounded),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
