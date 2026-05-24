part of 'agent_conversation_page.dart';

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
    required this.bottomKey,
    required this.messages,
    required this.todos,
    required this.thinking,
    required this.acceptanceCards,
    required this.pendingUserContent,
    required this.streamingAnswer,
    required this.streamingReasoning,
    required this.askError,
    required this.pendingUserAttachments,
    required this.messageAttachmentsById,
    required this.messageMediaResultsById,
    this.onTaskViewed,
  });

  final ScrollController controller;
  final Key bottomKey;
  final List<Message> messages;
  final List<Todo> todos;
  final bool thinking;
  final List<Widget> acceptanceCards;
  final String? pendingUserContent;
  final String streamingAnswer;
  final String streamingReasoning;
  final String? askError;
  final List<_AgentMessageAttachmentView> pendingUserAttachments;
  final Map<String, List<_AgentMessageAttachmentView>> messageAttachmentsById;
  final Map<String, List<_AgentMessageMediaResultView>> messageMediaResultsById;
  final Future<void> Function(Todo todo)? onTaskViewed;

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
      ..._buildMessageWidgets(context),
      if (acceptanceCards.isNotEmpty)
        _MessageFrame(
          author: context.t.app.title,
          time: t.ready,
          child: _AcceptanceCardStack(cards: acceptanceCards),
        ),
      if (pendingContent != null && pendingContent.isNotEmpty)
        _UserMessage(
          content: pendingContent,
          attachments: pendingUserAttachments,
        ),
      if (streamingContent.isNotEmpty)
        _AssistantTextMessage(
          content: streamingContent,
          time: t.thinking,
          onTaskViewed: onTaskViewed,
        )
      else if (thinking)
        _ThinkingMessage(reasoning: streamingReasoning),
      if (errorContent != null && errorContent.isNotEmpty)
        _AssistantTextMessage(
          content: errorContent,
          time: t.done,
          onTaskViewed: onTaskViewed,
        ),
      SizedBox(key: bottomKey, height: 1),
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

  List<Widget> _buildMessageWidgets(BuildContext context) {
    final widgets = <Widget>[];
    String? sourceUserMessageId;

    for (final message in messages) {
      if (message.role == 'assistant') {
        widgets.add(
          _AssistantTextMessage(
            content: message.content,
            time: context.t.chat.agentConversation.done,
            sourceMessage: message,
            onTaskViewed: onTaskViewed,
            createdTasks: _createdTasksForAssistantMessage(
              message: message,
              sourceUserMessageId: sourceUserMessageId,
            ),
            mediaResults: messageMediaResultsById[message.id] ??
                const <_AgentMessageMediaResultView>[],
          ),
        );
        sourceUserMessageId = null;
      } else {
        widgets.add(
          _UserMessage(
            content: message.content,
            attachments: messageAttachmentsById[message.id] ??
                const <_AgentMessageAttachmentView>[],
          ),
        );
        sourceUserMessageId = message.id;
      }
    }

    return widgets;
  }

  List<Todo> _createdTasksForAssistantMessage({
    required Message message,
    required String? sourceUserMessageId,
  }) {
    final sourceIds = <String>{message.id};
    final userMessageId = sourceUserMessageId?.trim();
    if (userMessageId != null && userMessageId.isNotEmpty) {
      sourceIds.add(userMessageId);
    }
    return agentTasksCreatedFromSources(todos, sourceIds);
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
  const _UserMessage({
    required this.content,
    this.attachments = const <_AgentMessageAttachmentView>[],
  });

  final String content;
  final List<_AgentMessageAttachmentView> attachments;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (content.trim().isNotEmpty)
                    Text(
                      content,
                      style: const TextStyle(
                        color: _AgentConversationPageState._ink,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                  if (attachments.isNotEmpty) ...[
                    if (content.trim().isNotEmpty)
                      const SizedBox(height: AgentDesignTokens.gapMd),
                    _MessageAttachmentStrip(attachments: attachments),
                  ],
                ],
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

final class _RuntimeMemoryCandidateCard extends StatelessWidget {
  const _RuntimeMemoryCandidateCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final SecretaryRuntimeApprovalItem item;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = context.t;
    final memoryText = _runtimeApprovalPrimaryText(item);

    return SlSurface(
      key: ValueKey('runtime_memory_candidate_card_${item.id}'),
      color: scheme.surface,
      borderColor: Colors.orange.shade700.withOpacity(0.32),
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: Colors.orange.shade700,
                size: 18,
              ),
              const SizedBox(width: AgentDesignTokens.gapSm),
              Expanded(
                child: Text(
                  t.chat.secretary.memory.cardTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              AgentStatusChip.needsApproval(
                label: t.chat.approvalPreview.needsApproval,
              ),
            ],
          ),
          const SizedBox(height: AgentDesignTokens.gapMd),
          Text(
            t.chat.secretary.memory.suggestedMemoryLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AgentDesignTokens.gapXs),
          Text(
            memoryText,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AgentDesignTokens.gapMd),
          Wrap(
            spacing: AgentDesignTokens.gapSm,
            runSpacing: AgentDesignTokens.gapSm,
            children: [
              FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(t.common.actions.accept),
              ),
              TextButton.icon(
                onPressed: onReject,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(t.common.actions.ignore),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _RuntimeCandidateApprovalCard extends StatelessWidget {
  const _RuntimeCandidateApprovalCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
    this.onEditTitle,
  });

  final SecretaryRuntimeApprovalItem item;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final ValueChanged<String>? onEditTitle;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = context.t;
    final title = _runtimeApprovalPrimaryText(item);
    final detail = _runtimeApprovalSecondaryText(item);

    return SlSurface(
      key: ValueKey('runtime_candidate_approval_card_${item.id}'),
      color: scheme.surface,
      borderColor: tokens.borderSubtle,
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, size: 18),
              const SizedBox(width: AgentDesignTokens.gapSm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              AgentStatusChip.needsApproval(
                label: t.chat.approvalPreview.needsApproval,
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: AgentDesignTokens.gapSm),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: AgentDesignTokens.gapMd),
          Wrap(
            spacing: AgentDesignTokens.gapSm,
            runSpacing: AgentDesignTokens.gapSm,
            children: [
              if (onEditTitle != null)
                OutlinedButton.icon(
                  key: ValueKey(
                    'runtime_candidate_approval_edit_title_${item.id}',
                  ),
                  onPressed: () => _showTitleEditor(context),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text(t.common.actions.edit),
                ),
              FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(t.common.actions.accept),
              ),
              TextButton.icon(
                onPressed: onReject,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(t.common.actions.ignore),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showTitleEditor(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RuntimeApprovalTitleDialog(item: item),
    );
    final nextTitle = title?.trim() ?? '';
    if (nextTitle.isEmpty) return;
    onEditTitle?.call(nextTitle);
  }
}

final class _RuntimeApprovalTitleDialog extends StatefulWidget {
  const _RuntimeApprovalTitleDialog({required this.item});

  final SecretaryRuntimeApprovalItem item;

  @override
  State<_RuntimeApprovalTitleDialog> createState() =>
      _RuntimeApprovalTitleDialogState();
}

final class _RuntimeApprovalTitleDialogState
    extends State<_RuntimeApprovalTitleDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.title);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      title: Text(t.common.actions.edit),
      content: TextField(
        key: ValueKey(
          'runtime_candidate_approval_title_field_${widget.item.id}',
        ),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.actions.cancel),
        ),
        FilledButton(
          key: ValueKey(
            'runtime_candidate_approval_save_title_${widget.item.id}',
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(t.common.actions.save),
        ),
      ],
    );
  }
}

String _runtimeApprovalPrimaryText(SecretaryRuntimeApprovalItem item) {
  final record = item.record ?? const <String, Object?>{};
  return _firstNonEmptyString([
    record['text'],
    record['content'],
    record['title'],
    record['subject'],
    item.title,
    item.reason,
    item.kind,
  ]);
}

String _runtimeApprovalSecondaryText(SecretaryRuntimeApprovalItem item) {
  final record = item.record ?? const <String, Object?>{};
  final primary = _runtimeApprovalPrimaryText(item);
  final secondary = _firstNonEmptyString([
    record['body'],
    record['summary'],
    record['description'],
    record['content'],
    item.reason,
  ]);
  return secondary == primary ? '' : secondary;
}

String _firstNonEmptyString(Iterable<Object?> values) {
  for (final value in values) {
    final text = '$value'.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

final class _Composer extends StatelessWidget {
  const _Composer({
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (attachments.isNotEmpty) ...[
              _AttachmentDraftStrip(
                attachments: attachments,
                onRemoveAttachment: onRemoveAttachment,
              ),
              const SizedBox(height: AgentDesignTokens.gapSm),
            ],
            Row(
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
                  key: const ValueKey('chat_attach'),
                  tooltip: t.attach,
                  onPressed: busy ? null : onAttach,
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
                    final enabled = !busy &&
                        (value.text.trim().isNotEmpty ||
                            attachments.isNotEmpty);
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
          ],
        ),
      ),
    );
  }
}

final class _AttachmentDraftStrip extends StatelessWidget {
  const _AttachmentDraftStrip({
    required this.attachments,
    required this.onRemoveAttachment,
  });

  final List<AttachmentDraftPayload> attachments;
  final ValueChanged<String> onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('agent_attachment_draft_strip'),
      spacing: AgentDesignTokens.gapSm,
      runSpacing: AgentDesignTokens.gapSm,
      children: [
        for (final attachment in attachments)
          InputChip(
            key: ValueKey('agent_attachment_chip_${attachment.localId}'),
            avatar: const Icon(Icons.attach_file_rounded, size: 16),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                attachment.normalizedFilename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onDeleted: () => onRemoveAttachment(attachment.localId),
          ),
      ],
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
