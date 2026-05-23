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
    return ColoredBox(
      color: AgentOperatingSystemTokens.background,
      child: Column(
        children: [
          _OperatingTopAppBar(
            pendingApprovals: _runtimeApprovalItems.length,
            webResearchActive: webResearchActive,
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
                  thinking: _thinking,
                  acceptanceCards: acceptanceCards,
                  pendingUserContent: _pendingUserContent,
                  streamingAnswer: _streamingAnswer,
                  askError: _askError,
                  pendingUserAttachments: _pendingUserAttachments,
                  messageAttachmentsById: _messageAttachmentsById,
                  messageMediaResultsById: _messageMediaResultsById,
                  onApproveMemory: (item) => unawaited(
                    _resolveRuntimeApproval(item, approve: true),
                  ),
                  onRejectMemory: (item) => unawaited(
                    _resolveRuntimeApproval(item, approve: false),
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
  });

  final int pendingApprovals;
  final bool webResearchActive;

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
            child: Row(
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
                ] else
                  const _OperatingModeChip(),
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
            ),
          ),
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
    required this.thinking,
    required this.acceptanceCards,
    required this.pendingUserContent,
    required this.streamingAnswer,
    required this.askError,
    required this.pendingUserAttachments,
    required this.messageAttachmentsById,
    required this.messageMediaResultsById,
    required this.onApproveMemory,
    required this.onRejectMemory,
    required this.onOpenTask,
  });

  final ScrollController controller;
  final Key bottomKey;
  final List<Message> messages;
  final RuntimeAgentState? runtimeState;
  final List<RuntimeWorkingSetRecord> taskRecords;
  final List<Todo> todos;
  final List<SecretaryRuntimeApprovalItem> approvalItems;
  final bool thinking;
  final List<Widget> acceptanceCards;
  final String? pendingUserContent;
  final String streamingAnswer;
  final String? askError;
  final List<_AgentMessageAttachmentView> pendingUserAttachments;
  final Map<String, List<_AgentMessageAttachmentView>> messageAttachmentsById;
  final Map<String, List<_AgentMessageMediaResultView>> messageMediaResultsById;
  final ValueChanged<SecretaryRuntimeApprovalItem> onApproveMemory;
  final ValueChanged<SecretaryRuntimeApprovalItem> onRejectMemory;
  final ValueChanged<RuntimeWorkingSetRecord> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var renderedActionCards = false;
    final processingLabels = _processingLabels();
    String? sourceUserMessageId;
    var renderedWebResearch = false;
    final suppressContextStrip = _hasOperatingWebResearchState(
      runtimeState: runtimeState,
      messages: messages,
    );
    final turnsById = <String, RuntimeConversationTurn>{
      for (final turn in runtimeState?.conversationTurns ??
          const <RuntimeConversationTurn>[])
        if (turn.turnId.trim().isNotEmpty) turn.turnId: turn,
    };

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
                  mediaResults: messageMediaResultsById[message.id] ??
                      const <_AgentMessageMediaResultView>[],
                ),
        );
        if (isWebResearch) {
          renderedWebResearch = true;
        }
        final createdTaskCards =
            _createdTaskCards(sourceUserMessageId, message.id);
        sourceUserMessageId = null;
        if (_isLatestAssistantMessage(index)) {
          final actionCards = <Widget>[
            ...createdTaskCards,
            ..._approvalCards(),
          ];
          if (actionCards.isNotEmpty) {
            children.add(_OperatingActionCardGrid(children: actionCards));
            renderedActionCards = true;
          }
          if (!suppressContextStrip) {
            children.add(_OperatingContextStrip(state: runtimeState));
          }
        } else {
          children.addAll(createdTaskCards);
        }
      } else {
        children.add(
          _OperatingUserBubble(
            content: message.content,
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
          attachments: pendingUserAttachments,
        ),
      );
    }
    if (streamingAnswer.trim().isNotEmpty) {
      children.add(
        _OperatingAssistantBubble(
          content: streamingAnswer.trim(),
          messageId: 'streaming',
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

  List<Widget> _approvalCards() {
    final memoryApprovals = approvalItems
        .where((item) => item.kind == 'memory_confirmation')
        .toList(growable: false);
    if (memoryApprovals.isNotEmpty) {
      return [
        for (final item in memoryApprovals)
          _OperatingMemoryCandidateCard(
            item: item,
            onApprove: () => onApproveMemory(item),
            onReject: () => onRejectMemory(item),
          ),
      ];
    }
    return acceptanceCards;
  }

  List<String> _processingLabels() {
    final labels = <String>['router'];
    if (taskRecords.isNotEmpty || todos.isNotEmpty) {
      labels.add('task-management');
    }
    if (approvalItems.any((item) => item.kind == 'memory_confirmation') ||
        (runtimeState?.memoryRecords.isNotEmpty ?? false)) {
      labels.add('memory-capture');
    }
    if (taskRecords.isNotEmpty ||
        (runtimeState?.memoryRecords.isNotEmpty ?? false)) {
      labels.add('vault write');
    }
    return labels.length == 1 ? const <String>[] : labels;
  }
}

final class _OperatingActionCardGrid extends StatelessWidget {
  const _OperatingActionCardGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 720 && children.length > 1;
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

final class _OperatingUserBubble extends StatelessWidget {
  const _OperatingUserBubble({
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
            color: AgentOperatingSystemTokens.surface,
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
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

final class _OperatingAssistantBubble extends StatelessWidget {
  const _OperatingAssistantBubble({
    required this.content,
    required this.messageId,
    this.mediaResults = const <_AgentMessageMediaResultView>[],
  });

  final String content;
  final String messageId;
  final List<_AgentMessageMediaResultView> mediaResults;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surface,
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(
                  width: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AgentOperatingSystemTokens.secondary,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(
                            AgentOperatingSystemTokens.radiusLg),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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
                        if (mediaResults.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          KeyedSubtree(
                            key: ValueKey(
                              'agent_assistant_media_results_$messageId',
                            ),
                            child: _AssistantRuntimeMediaResults(
                              results: mediaResults,
                            ),
                          ),
                        ],
                      ],
                    ),
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

final class _OperatingProcessingStrip extends StatelessWidget {
  const _OperatingProcessingStrip({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surfaceContainerLow,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
          border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.settings_input_component_rounded,
                size: 14,
                color: AgentOperatingSystemTokens.secondary,
              ),
              const SizedBox(width: 8),
              for (var index = 0; index < labels.length; index++) ...[
                Text(
                  labels[index],
                  style: AgentOperatingSystemTokens.code.copyWith(
                    color: labels[index] == 'vault write'
                        ? AgentOperatingSystemTokens.secondary
                        : AgentOperatingSystemTokens.onSurfaceVariant,
                    fontWeight: labels[index] == 'vault write'
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
                if (index < labels.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Text(
                      '/',
                      style: TextStyle(
                        color: AgentOperatingSystemTokens.outlineVariant,
                        fontSize: 11,
                        height: 1,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
