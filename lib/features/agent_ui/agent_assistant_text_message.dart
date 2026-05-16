part of 'agent_conversation_page.dart';

final class _AssistantTextMessage extends StatelessWidget {
  const _AssistantTextMessage({
    required this.content,
    required this.time,
    this.createdTasks = const <Todo>[],
    this.sourceMessage,
    this.onTaskViewed,
  });

  final String content;
  final String time;
  final List<Todo> createdTasks;
  final Message? sourceMessage;
  final Future<void> Function(Todo todo)? onTaskViewed;

  Future<bool> _openInAppTodo(BuildContext context, String href) async {
    final parsed = parseTodoDeepLink(href);
    if (parsed == null) return false;

    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (sessionKey == null) return false;

    Todo? todo;
    try {
      todo = await AppBackendScope.of(context).getTodoById(
        sessionKey,
        parsed.todoId,
      );
    } catch (_) {
      todo = null;
    }
    if (todo == null || !context.mounted) return false;

    await showAgentTaskDetailSheet(
      context: context,
      todo: todo,
      onTaskViewed: onTaskViewed,
    );
    return true;
  }

  Future<bool> _openInAppEvent(BuildContext context, String href) async {
    final parsed = parseEventDeepLink(href);
    if (parsed == null) return false;

    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (sessionKey == null) return false;

    Event? event;
    try {
      event = await AppBackendScope.of(context).getEventById(
        sessionKey,
        parsed.eventId,
      );
    } catch (_) {
      event = null;
    }
    if (event == null || !context.mounted) return false;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventViewerPage(event: event!)),
    );
    return true;
  }

  Future<bool> _openInAppAttachment(BuildContext context, String href) async {
    final parsed = parseAttachmentDeepLink(href);
    if (parsed == null) return false;

    await AttachmentViewerPage.openBySha(
      context,
      attachmentSha256: parsed.attachmentSha256,
      initialContentKind: parsed.kind,
      initialChunkIndex: parsed.chunk,
    );
    return true;
  }

  Future<bool> _openInAppMessage(BuildContext context, String href) async {
    final parsed = parseMessageDeepLink(href);
    if (parsed == null) return false;

    await MessageViewerPage.openById(context, messageId: parsed.messageId);
    return true;
  }

  Future<bool> _openInAppLink(BuildContext context, String href) async {
    if (await _openInAppTodo(context, href)) return true;
    if (!context.mounted) return false;
    if (await _openInAppEvent(context, href)) return true;
    if (!context.mounted) return false;
    if (await _openInAppAttachment(context, href)) return true;
    if (!context.mounted) return false;
    return _openInAppMessage(context, href);
  }

  Future<void> _showUnsupportedSecondLoopLink(
    BuildContext context,
    String href,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t.errors.loadFailed(error: 'unsupported_secondloop_link'),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleMarkdownHref(
    BuildContext context,
    String? href, {
    required ChatAnswerCitationController citationController,
  }) async {
    final target = href?.trim();
    if (target == null || target.isEmpty) return;

    final handledCitation = await citationController.handleCitationTap(
      context,
      href: target,
      onOpenDirectSource: (sourceHref) => _openInAppLink(context, sourceHref),
    );
    if (handledCitation) return;

    await handleChatMarkdownTapLink(
      target,
      handleInApp: (sourceHref) => _openInAppLink(context, sourceHref),
      handleUnsupportedSecondLoopLink: (sourceHref) =>
          _showUnsupportedSecondLoopLink(context, sourceHref),
    );
  }

  Future<void> _handleAssistantSuggestion(
    BuildContext context,
    Message sourceMessage,
    ActionSuggestion suggestion,
    int index,
  ) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (sessionKey == null) return;

    final settings = await ActionsSettingsStore.load();
    if (!context.mounted) return;

    final timeResolution = _resolveSuggestionTime(
      context,
      suggestion.whenText,
      settings,
    );

    if (suggestion.type == 'event') {
      final initialLocal =
          timeResolution?.candidates.firstOrNull?.dueAtLocal ?? DateTime.now();
      final startLocal = await showSlDateTimePickerDialog(
        context,
        initialLocal: initialLocal,
        firstDate: DateTime(initialLocal.year - 1),
        lastDate: DateTime(initialLocal.year + 3),
        title: context.t.actions.calendar.pickCustom,
      );
      if (startLocal == null || !context.mounted) return;

      final startUtc = startLocal.toUtc();
      final endUtc = startLocal.add(const Duration(hours: 1)).toUtc();
      await backend.upsertEvent(
        sessionKey,
        id: 'event:${sourceMessage.id}:$index',
        title: suggestion.title.trim(),
        startAtMs: startUtc.millisecondsSinceEpoch,
        endAtMs: endUtc.millisecondsSinceEpoch,
        tz: _formatTzOffset(startLocal.timeZoneOffset),
        sourceEntryId: sourceMessage.id,
      );
      if (!context.mounted) return;
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      return;
    }

    if (suggestion.type != 'todo') return;

    final decision = await showCaptureTodoSuggestionSheet(
      context,
      title: suggestion.title,
      timeResolution: timeResolution,
    );
    if (decision == null || !context.mounted) return;

    final todoId = 'todo:${sourceMessage.id}:$index';
    switch (decision) {
      case CaptureTodoScheduleDecision(:final dueAtLocal):
        await createTodoWithFollowup(
          backend,
          sessionKey,
          id: todoId,
          title: suggestion.title.trim(),
          dueAtMs: dueAtLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: sourceMessage.id,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        break;
      case CaptureTodoReviewDecision():
        final nextLocal = ReviewBackoff.initialNextReviewAt(
          DateTime.now(),
          settings,
        );
        await createTodoWithFollowup(
          backend,
          sessionKey,
          id: todoId,
          title: suggestion.title.trim(),
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: sourceMessage.id,
          reviewStage: 0,
          nextReviewAtMs: nextLocal.toUtc().millisecondsSinceEpoch,
          lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        break;
      case CaptureTodoNoThanksDecision():
        return;
    }
    if (!context.mounted) return;
    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
  }

  LocalTimeResolution? _resolveSuggestionTime(
    BuildContext context,
    String? whenText,
    ActionsSettings settings,
  ) {
    final normalized = whenText?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return LocalTimeResolver.resolve(
      normalized,
      DateTime.now(),
      locale: Localizations.localeOf(context),
      dayEndMinutes: settings.dayEndMinutes,
      firstDayOfWeekIndex:
          MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );
  }

  String _formatTzOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final hours = abs.inHours.toString().padLeft(2, '0');
    final minutes = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseAssistantMessageActions(content);
    final displayText = parsed.displayText.trim();
    final message = sourceMessage;
    final actionSuggestions = message == null
        ? const <ActionSuggestion>[]
        : parsed.suggestions?.suggestions ?? const <ActionSuggestion>[];
    final citationController = ChatAnswerCitationController(
      parseChatAnswerEvidence(message?.citationsJson),
    );
    final evidence = citationController.evidence;
    const textStyle = TextStyle(
      color: _AgentConversationPageState._ink,
      fontWeight: FontWeight.w600,
      height: 1.5,
    );

    return _MessageFrame(
      author: context.t.app.title,
      time: time,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _AgentConversationPageState._panel,
                  borderRadius:
                      BorderRadius.circular(AgentDesignTokens.radiusMd),
                  border: Border.all(color: _AgentConversationPageState._line),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgentDesignTokens.gapLg,
                    vertical: AgentDesignTokens.gapMd,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (displayText.isNotEmpty)
                        buildChatMarkdownPreviewBody(
                          context,
                          key: message == null
                              ? null
                              : ValueKey(
                                  'agent_assistant_markdown_${message.id}'),
                          text: displayText,
                          selectable: true,
                          bodyStyle: textStyle,
                          citationLabelResolver:
                              citationController.chipLabelForHref,
                          onTapRichLink: (href) => _handleMarkdownHref(
                            context,
                            href,
                            citationController: citationController,
                          ),
                          onTapLink: (_, href, __) => unawaited(
                            _handleMarkdownHref(
                              context,
                              href,
                              citationController: citationController,
                            ),
                          ),
                        ),
                      if ((evidence != null && evidence.hasEvidence) ||
                          actionSuggestions.isNotEmpty)
                        ChatAssistantMessageFooter(
                          evidence: evidence,
                          onOpenSources: () => unawaited(
                            citationController.openEvidence(
                              context,
                              canOpenDirectSource: canOpenChatMarkdownHref,
                              onOpenDirectSource: (href) =>
                                  _openInAppLink(context, href),
                            ),
                          ),
                          actionSuggestions: actionSuggestions,
                          onTapActionSuggestion: message == null
                              ? (_, __) {}
                              : (suggestion, index) => unawaited(
                                    _handleAssistantSuggestion(
                                      context,
                                      message,
                                      suggestion,
                                      index,
                                    ),
                                  ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          for (final task in createdTasks) ...[
            const SizedBox(height: AgentDesignTokens.gapMd),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: AgentCreatedTaskCard(
                todo: task,
                onOpenTask: () => unawaited(
                  showAgentTaskDetailSheet(
                    context: context,
                    todo: task,
                    onTaskViewed: onTaskViewed,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on List<DueCandidate> {
  DueCandidate? get firstOrNull => isEmpty ? null : first;
}
