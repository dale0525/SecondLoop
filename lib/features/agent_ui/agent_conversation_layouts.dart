part of 'agent_conversation_page.dart';

extension _AgentConversationLayouts on _AgentConversationPageState {
  // ignore: unused_element
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_conversationTurnPage.hasMoreBefore)
                      _LoadEarlierRuntimeTurnsButton(
                        loading: _loadingOlderRuntimeTurns,
                        onPressed: _loadOlderRuntimeTurns,
                      ),
                    Expanded(
                      child: _MessageList(
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
                        pendingUserAttachments: _pendingUserAttachments,
                        messageAttachmentsById: _messageAttachmentsById,
                        messageMediaResultsById: _messageMediaResultsById,
                        onTaskViewed: _recordTaskFocus,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AgentDesignTokens.gapLg),
          _Composer(
            controller: _controller,
            focusNode: _focusNode,
            busy: _sending || _thinking,
            attachments: _pendingAttachmentDrafts,
            onAttach: () => unawaited(_pickAttachments()),
            onRemoveAttachment: _removePendingAttachment,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildOperatingSystemMobileShell(
    BuildContext context, {
    required List<Widget> acceptanceCards,
    required List<Todo> todos,
  }) {
    final webResearchActive = _hasOperatingWebResearchState(
      runtimeState: _runtimeAgentState,
      messages: _messages,
    );
    final vaultUploadActive = _hasOperatingVaultUploadState(
      runtimeState: _runtimeAgentState,
      attachmentsByMessageId: _messageAttachmentsById,
    );
    return ColoredBox(
      color: AgentOperatingSystemTokens.background,
      child: Column(
        children: [
          _OperatingTopAppBar(
            pendingApprovals: _runtimeApprovalItems.length,
            webResearchActive: webResearchActive,
            vaultUploadActive: vaultUploadActive,
          ),
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
                return _OperatingMessageList(
                  controller: _scrollController,
                  bottomKey: _messageListBottomKey,
                  messages: _messages,
                  runtimeState: _runtimeAgentState,
                  taskRecords: _runtimeAgentState?.tasks ??
                      const <RuntimeWorkingSetRecord>[],
                  todos: todos,
                  approvalItems: _runtimeApprovalItems,
                  busyApprovalIds: _busyApprovalIds,
                  thinking: _thinking,
                  acceptanceCards: acceptanceCards,
                  pendingUserContent: _pendingUserContent,
                  streamingAnswer: _streamingAnswer,
                  askError: _askError,
                  pendingUserAttachments: _pendingUserAttachments,
                  messageAttachmentsById: _messageAttachmentsById,
                  messageMediaResultsById: _messageMediaResultsById,
                  onApproveApproval: (item) => unawaited(
                    _resolveRuntimeApproval(item, approve: true),
                  ),
                  onRejectApproval: (item) => unawaited(
                    _resolveRuntimeApproval(item, approve: false),
                  ),
                  onEditApprovalTitle: (item, title) => unawaited(
                    _patchRuntimeApprovalTitle(item, title),
                  ),
                  onOpenTask: (record) => unawaited(
                    showAgentTaskDetailSheet(
                      context: context,
                      todo: agentTodoFromRuntimeTask(record),
                      onTaskViewed: _recordTaskFocus,
                    ),
                  ),
                );
              },
            ),
          ),
          _OperatingComposer(
            controller: _controller,
            focusNode: _focusNode,
            busy: _sending || _thinking,
            placeholder: webResearchActive ? 'Ask a follow-up...' : null,
            followUpMode: webResearchActive,
            attachments: _pendingAttachmentDrafts,
            onAttach: () => unawaited(_pickAttachments()),
            onRemoveAttachment: _removePendingAttachment,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Future<void> _recordTaskFocus(Todo todo) async {
    final entityId = todo.id.trim();
    final conversationId = widget.conversation.id.trim();
    if (entityId.isEmpty || conversationId.isEmpty) return;

    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final vaultId = cloudAuthScope?.controller.uid?.trim() ?? '';
    if (cloudAuthScope == null || vaultId.isEmpty) return;

    final Object? configuredSender = widget.runtimeConversationSender;
    final ChatRuntimeEntityFocusSender sender =
        configuredSender is ChatRuntimeEntityFocusSender
            ? configuredSender
            : SecretaryRuntimeConversationSender.hostedManagedPro(
                apiBaseUrl: cloudAuthScope.gatewayConfig.baseUrl,
                hostedSessionTokenGetter: cloudAuthScope.controller.getIdToken,
              );
    try {
      await sender.recordEntityFocus(
        vaultId: vaultId,
        conversationId: conversationId,
        entityType: 'task',
        entityId: entityId,
        title: todo.title,
      );
    } catch (_) {
      // Task viewing should never block task inspection.
    }
  }
}

final class _OperatingTopAppBar extends StatelessWidget {
  const _OperatingTopAppBar({
    required this.pendingApprovals,
    required this.webResearchActive,
    required this.vaultUploadActive,
  });

  final int pendingApprovals;
  final bool webResearchActive;
  final bool vaultUploadActive;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AgentOperatingSystemTokens.background,
        border: Border(
          bottom: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showVaultUploadChip =
                    vaultUploadActive && constraints.maxWidth >= 430;
                return Row(
                  children: [
                    if (!webResearchActive) ...[
                      ClipOval(
                        child: Image.asset(
                          'assets/icon/tray_icon.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        webResearchActive ? 'SecondLoop' : 'SecondLoop Agent',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgentOperatingSystemTokens.headlineMd,
                      ),
                    ),
                    if (webResearchActive) ...[
                      const _OperatingPrimaryModeChip(),
                      const SizedBox(width: 6),
                      const _OperatingWebResearchModeChip(),
                    ] else ...[
                      const _OperatingModeChip(),
                      if (showVaultUploadChip) ...[
                        const SizedBox(width: 6),
                        const _OperatingVaultUploadModeChip(),
                      ],
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Notifications',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final message = pendingApprovals == 0
                            ? 'No pending approvals'
                            : '$pendingApprovals pending approval(s)';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      },
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: AgentOperatingSystemTokens.onSurfaceVariant,
                      ),
                    ),
                    if (webResearchActive) ...[
                      const SizedBox(width: 4),
                      ClipOval(
                        child: Image.asset(
                          'assets/icon/tray_icon.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

final class _OperatingVaultUploadModeChip extends StatelessWidget {
  const _OperatingVaultUploadModeChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerHigh,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: 13,
              color: AgentOperatingSystemTokens.secondary,
            ),
            SizedBox(width: 4),
            Text(
              'Vault Upload',
              style: TextStyle(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingPrimaryModeChip extends StatelessWidget {
  const _OperatingPrimaryModeChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'Managed Pro',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

final class _OperatingWebResearchModeChip extends StatelessWidget {
  const _OperatingWebResearchModeChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerHigh,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.public_rounded,
              size: 13,
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
            SizedBox(width: 4),
            Text(
              'web-research',
              style: TextStyle(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingModeChip extends StatelessWidget {
  const _OperatingModeChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainer,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OperatingStatusDot(),
            SizedBox(width: 6),
            Text(
              'Managed Pro',
              style: TextStyle(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingStatusDot extends StatelessWidget {
  const _OperatingStatusDot();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 8,
      height: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.secondary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

final class _OperatingMessageList extends StatelessWidget {
  const _OperatingMessageList({
    required this.controller,
    required this.bottomKey,
    required this.messages,
    required this.runtimeState,
    required this.taskRecords,
    required this.todos,
    required this.approvalItems,
    required this.busyApprovalIds,
    required this.thinking,
    required this.acceptanceCards,
    required this.pendingUserContent,
    required this.streamingAnswer,
    required this.askError,
    required this.pendingUserAttachments,
    required this.messageAttachmentsById,
    required this.messageMediaResultsById,
    required this.onApproveApproval,
    required this.onRejectApproval,
    required this.onEditApprovalTitle,
    required this.onOpenTask,
  });

  final ScrollController controller;
  final Key bottomKey;
  final List<Message> messages;
  final RuntimeAgentState? runtimeState;
  final List<RuntimeWorkingSetRecord> taskRecords;
  final List<Todo> todos;
  final List<SecretaryRuntimeApprovalItem> approvalItems;
  final Set<String> busyApprovalIds;
  final bool thinking;
  final List<Widget> acceptanceCards;
  final String? pendingUserContent;
  final String streamingAnswer;
  final String? askError;
  final List<_AgentMessageAttachmentView> pendingUserAttachments;
  final Map<String, List<_AgentMessageAttachmentView>> messageAttachmentsById;
  final Map<String, List<_AgentMessageMediaResultView>> messageMediaResultsById;
  final ValueChanged<SecretaryRuntimeApprovalItem> onApproveApproval;
  final ValueChanged<SecretaryRuntimeApprovalItem> onRejectApproval;
  final _OperatingApprovalTitleChanged onEditApprovalTitle;
  final ValueChanged<RuntimeWorkingSetRecord> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var renderedActionCards = false;
    final processingLabels = _processingLabels();
    String? sourceUserMessageId;
    var renderedWebResearch = false;
    final renderedPendingIntentIds = <String>{};
    final suppressContextStrip = _hasOperatingWebResearchState(
      runtimeState: runtimeState,
      messages: messages,
    );
    final turnsById = <String, RuntimeConversationTurn>{
      for (final turn in runtimeState?.conversationTurns ??
          const <RuntimeConversationTurn>[])
        if (turn.turnId.trim().isNotEmpty) turn.turnId: turn,
    };
    if (messages.isNotEmpty && messages.first.createdAtMs > 0) {
      children.add(_OperatingDateChip(createdAtMs: messages.first.createdAtMs));
    }

    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final next = index + 1 < messages.length ? messages[index + 1] : null;
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
              : _OperatingAssistantBubble(
                  content: message.content,
                  messageId: message.id,
                  createdAtMs: message.createdAtMs,
                  mediaResults: messageMediaResultsById[message.id] ??
                      const <_AgentMessageMediaResultView>[],
                ),
        );
        if (isWebResearch) {
          renderedWebResearch = true;
        }
        children.addAll(
          _operatingPendingIntentCards(
            state: runtimeState,
            userMessageId: sourceUserMessageId,
            assistantMessageId: message.id,
            renderedIds: renderedPendingIntentIds,
          ),
        );
        final createdTaskCards =
            _createdTaskCards(sourceUserMessageId, message.id);
        sourceUserMessageId = null;
        if (_isLatestAssistantMessage(index)) {
          final actionCards = <Widget>[
            ...createdTaskCards,
            ..._approvalCards(context),
          ];
          if (actionCards.isNotEmpty) {
            children.add(_OperatingActionCardGrid(children: actionCards));
            renderedActionCards = true;
          }
          if (!suppressContextStrip && _hasContextStripState()) {
            children.add(_OperatingContextStrip(state: runtimeState));
          }
        } else {
          children.addAll(createdTaskCards);
        }
      } else {
        children.add(
          _OperatingUserBubble(
            content: message.content,
            createdAtMs: message.createdAtMs,
            attachments: messageAttachmentsById[message.id] ??
                const <_AgentMessageAttachmentView>[],
          ),
        );
        if (next?.role == 'assistant' && processingLabels.isNotEmpty) {
          children.add(_OperatingProcessingStrip(labels: processingLabels));
        }
        sourceUserMessageId = message.id;
      }
    }

    final pendingContent = pendingUserContent?.trim();
    if (pendingContent != null && pendingContent.isNotEmpty) {
      children.add(
        _OperatingUserBubble(
          content: pendingContent,
          createdAtMs: null,
          attachments: pendingUserAttachments,
        ),
      );
    }
    if (streamingAnswer.trim().isNotEmpty) {
      children.add(
        _OperatingAssistantBubble(
          content: streamingAnswer.trim(),
          messageId: 'streaming',
          createdAtMs: null,
        ),
      );
    } else if (thinking) {
      children.add(const _OperatingProcessingStrip(labels: ['runtime']));
    }
    if (askError?.trim().isNotEmpty ?? false) {
      children.add(
        _OperatingAssistantBubble(
          content: askError!.trim(),
          messageId: 'error',
          createdAtMs: null,
        ),
      );
    }
    if (!renderedActionCards && acceptanceCards.isNotEmpty) {
      children.add(_OperatingActionCardGrid(children: acceptanceCards));
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

    return ListView.separated(
      key: const ValueKey('agent_operating_message_list'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 18),
      itemBuilder: (context, index) => children[index],
    );
  }

  bool _isLatestAssistantMessage(int index) {
    for (var cursor = index + 1; cursor < messages.length; cursor++) {
      if (messages[cursor].role == 'assistant') return false;
    }
    return true;
  }

  List<Widget> _createdTaskCards(String? userMessageId, String assistantId) {
    final sourceIds = {assistantId, if (userMessageId != null) userMessageId};
    final records = taskRecords.where((record) {
      final sourceId = _firstOperatingString([
        record.raw['source_message_id'],
        record.raw['sourceMessageId'],
        record.raw['source_entry_id'],
        record.raw['sourceEntryId'],
      ]);
      return sourceId == null || sourceIds.contains(sourceId);
    }).toList(growable: false);
    return [
      for (final record in records)
        _OperatingTaskCreatedCard(
          record: record,
          onOpen: () => onOpenTask(record),
        ),
    ];
  }

  List<Widget> _approvalCards(BuildContext context) {
    if (approvalItems.isEmpty) return acceptanceCards;
    if (runtimeState == null && acceptanceCards.isNotEmpty) {
      return acceptanceCards;
    }
    return [
      for (final item in approvalItems)
        if (item.kind == 'memory_confirmation')
          _OperatingMemoryCandidateCard(
            item: item,
            onApprove: () => onApproveApproval(item),
            onReject: () => onRejectApproval(item),
          )
        else if (_isOperatingActionItemCandidate(item))
          _OperatingActionItemCandidateCard(
            item: item,
            onCreate: busyApprovalIds.contains(item.id)
                ? null
                : () => onApproveApproval(item),
            onDismiss: busyApprovalIds.contains(item.id)
                ? null
                : () => onRejectApproval(item),
          )
        else if (item.kind == 'reminder_confirmation')
          _OperatingReminderCandidateCard(
            item: item,
            onApprove: busyApprovalIds.contains(item.id)
                ? null
                : () => onApproveApproval(item),
            onReject: busyApprovalIds.contains(item.id)
                ? null
                : () => onRejectApproval(item),
          )
        else if (item.kind == 'recurring_reminder_confirmation')
          _OperatingRecurringReminderCandidateCard(
            item: item,
            onApprove: () => onApproveApproval(item),
            onReject: () => onRejectApproval(item),
            onEditTitle: item.editableFields.contains('title')
                ? (title) => onEditApprovalTitle(item, title)
                : null,
          )
        else if (item.kind == 'task_mutation_confirmation' &&
            isTaskTitleMutationApproval(item))
          TaskMutationApprovalCard(
            item: item,
            taskRecords: taskRecords,
            contextSnapshot: runtimeState?.latestContextSnapshot,
            auditRefs:
                runtimeState?.auditRefs ?? const <Map<String, Object?>>[],
            recentEntityRefs: runtimeState?.recentEntityRefs ??
                const <Map<String, Object?>>[],
            busy: busyApprovalIds.contains(item.id),
            onApprove: busyApprovalIds.contains(item.id)
                ? null
                : () => onApproveApproval(item),
            onReject: busyApprovalIds.contains(item.id)
                ? null
                : () => onRejectApproval(item),
            onEditTitle: item.editableFields.contains('title')
                ? (title) => onEditApprovalTitle(item, title)
                : null,
          )
        else if (item.kind == 'task_mutation_confirmation')
          ApprovalPreviewCard(
            change: _approvalPreviewChange(context, item),
            onApprove: busyApprovalIds.contains(item.id)
                ? null
                : () => onApproveApproval(item),
            onReject: busyApprovalIds.contains(item.id)
                ? null
                : () => onRejectApproval(item),
          )
        else if (item.kind == 'calendar_event_confirmation')
          CalendarEventApprovalCard(
            item: item,
            contextSnapshot: runtimeState?.latestContextSnapshot,
            auditRefs:
                runtimeState?.auditRefs ?? const <Map<String, Object?>>[],
            busy: busyApprovalIds.contains(item.id),
            onApprove: busyApprovalIds.contains(item.id)
                ? null
                : () => onApproveApproval(item),
            onReject: busyApprovalIds.contains(item.id)
                ? null
                : () => onRejectApproval(item),
            onEdit: null,
          )
        else
          _RuntimeCandidateApprovalCard(
            item: item,
            onApprove: busyApprovalIds.contains(item.id)
                ? null
                : () => onApproveApproval(item),
            onReject: busyApprovalIds.contains(item.id)
                ? null
                : () => onRejectApproval(item),
          ),
    ];
  }

  List<String> _processingLabels() {
    final labels = <String>['router'];
    final hasAttachments =
        messageAttachmentsById.values.any((items) => items.isNotEmpty);
    final hasCalendarApproval =
        approvalItems.any((item) => item.kind == 'calendar_event_confirmation');
    final hasMediaResult = messageMediaResultsById.values.any(
      (results) => results.any((result) => result.hasVisibleContent),
    );
    final mediaResults = messageMediaResultsById.values
        .expand((results) => results)
        .where((result) => result.hasVisibleContent)
        .toList(growable: false);
    final hasAudioMediaResult =
        mediaResults.any((result) => result.isAudioResult);
    final highFidelityConfirmation = mediaResults
        .map((result) => result.processingConfirmationLabel?.trim() ?? '')
        .where((label) => label.isNotEmpty)
        .firstOrNull;
    final hasDocumentMediaAttachment = messageAttachmentsById.values.any(
      (items) => items.any(
        (attachment) =>
            attachment.isImage ||
            attachment.mimeType.trim().toLowerCase() == 'application/pdf',
      ),
    );
    final hasAudioAttachment = messageAttachmentsById.values.any(
      (items) => items.any((attachment) => attachment.isAudio),
    );
    if (hasAttachments) {
      if (hasCalendarApproval) {
        labels.add('email-analysis');
      } else if (hasAudioAttachment || hasAudioMediaResult) {
        labels.add('audio-transcription');
        labels.add('meeting-minutes');
      } else if (hasDocumentMediaAttachment || hasMediaResult) {
        labels.add('ocr');
        labels.add('summarize');
      } else {
        labels.add('attachment-ingest');
      }
    }
    if (taskRecords.isNotEmpty || todos.isNotEmpty) {
      labels.add('task-management');
    }
    final hasMemoryCandidate =
        approvalItems.any((item) => item.kind == 'memory_confirmation');
    final hasMemoryContext = runtimeState?.memoryRecords.isNotEmpty ?? false;
    if (hasMemoryContext || hasMemoryCandidate) {
      labels.add('memory-capture');
    }
    if (hasCalendarApproval) {
      labels.add('calendar-skill');
    }
    if (highFidelityConfirmation != null) {
      labels.add(highFidelityConfirmation);
    }
    if (taskRecords.isNotEmpty || hasMemoryContext || hasMediaResult) {
      labels.add(hasMediaResult ? 'source synced to Vault' : 'vault write');
    }
    return labels.length == 1 ? const <String>[] : labels;
  }

  bool _hasContextStripState() {
    final state = runtimeState;
    if (taskRecords.isNotEmpty || todos.isNotEmpty) return true;
    if (state == null) return false;
    if (state.recentEntityRefs.isNotEmpty || state.memoryRecords.isNotEmpty) {
      return true;
    }
    return state.workingSetRecords.any(
      (record) =>
          record.kind == 'file' ||
          record.kind == 'attachment' ||
          record.kind == 'media_result',
    );
  }
}

bool _hasOperatingVaultUploadState({
  required RuntimeAgentState? runtimeState,
  required Map<String, List<_AgentMessageAttachmentView>>
      attachmentsByMessageId,
}) {
  if (attachmentsByMessageId.values.any((items) => items.isNotEmpty)) {
    return true;
  }
  return runtimeState?.workingSetRecords.any(
        (record) =>
            record.kind == 'file' ||
            record.kind == 'attachment' ||
            record.kind == 'media_result',
      ) ??
      false;
}

final class _OperatingActionCardGrid extends StatelessWidget {
  const _OperatingActionCardGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 960 && children.length > 1;
        if (!useRow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(height: 16),
                children[index],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: 16),
              Expanded(child: children[index]),
            ],
          ],
        );
      },
    );
  }
}
