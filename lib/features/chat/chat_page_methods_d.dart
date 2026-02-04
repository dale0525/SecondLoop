part of 'chat_page.dart';

extension _ChatPageStateMethodsD on _ChatPageState {
  Future<void> _linkMessageToTodo(Message message) async {
    if (!mounted) return;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    final linkedTodoInfo = await _resolveLinkedTodoInfo(message);
    if (!mounted) return;
    final shouldMoveExisting =
        linkedTodoInfo != null && !linkedTodoInfo.isSourceEntry;

    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return;
    }

    final nowLocal = DateTime.now();
    final targets = <TodoLinkTarget>[];
    final todosById = <String, Todo>{};
    for (final todo in todos) {
      if (todo.status == 'dismissed') continue;
      todosById[todo.id] = todo;
      final dueMs = todo.dueAtMs;
      targets.add(
        TodoLinkTarget(
          id: todo.id,
          title: todo.title,
          status: todo.status,
          dueLocal: dueMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(dueMs, isUtc: true)
                  .toLocal(),
        ),
      );
    }
    if (targets.isEmpty) return;

    final ranked = await _rankTodoCandidatesWithSemanticMatches(
      backend,
      sessionKey,
      query: message.content,
      targets: targets,
      nowLocal: nowLocal,
      limit: 10,
    );
    final selectedTodoId = await _showTodoNoteLinkSheet(
      allTargets: targets,
      ranked: ranked,
    );
    if (selectedTodoId == null || !mounted) return;

    final selected = todosById[selectedTodoId];
    if (selected == null) return;

    try {
      if (shouldMoveExisting && linkedTodoInfo.todo.id != selected.id) {
        String? sourceActivityId;
        try {
          final activities = await backend.listTodoActivities(
              sessionKey, linkedTodoInfo.todo.id);
          for (final activity in activities) {
            if (activity.sourceMessageId == message.id) {
              sourceActivityId = activity.id;
              break;
            }
          }
        } catch (_) {
          sourceActivityId = null;
        }

        if (sourceActivityId != null) {
          await backend.moveTodoActivity(
            sessionKey,
            activityId: sourceActivityId,
            toTodoId: selected.id,
          );
        } else {
          final activity = await backend.appendTodoNote(
            sessionKey,
            todoId: selected.id,
            content: message.content.trim(),
            sourceMessageId: message.id,
          );

          final attachmentsBackend = backend is AttachmentsBackend
              ? backend as AttachmentsBackend
              : null;
          if (attachmentsBackend != null) {
            try {
              final attachments = await attachmentsBackend
                  .listMessageAttachments(sessionKey, message.id);
              for (final attachment in attachments) {
                await backend.linkAttachmentToTodoActivity(
                  sessionKey,
                  activityId: activity.id,
                  attachmentSha256: attachment.sha256,
                );
              }
            } catch (_) {
              // ignore
            }
          }
        }
      } else {
        final activity = await backend.appendTodoNote(
          sessionKey,
          todoId: selected.id,
          content: message.content.trim(),
          sourceMessageId: message.id,
        );

        final attachmentsBackend = backend is AttachmentsBackend
            ? backend as AttachmentsBackend
            : null;
        if (attachmentsBackend != null) {
          try {
            final attachments = await attachmentsBackend.listMessageAttachments(
                sessionKey, message.id);
            for (final attachment in attachments) {
              await backend.linkAttachmentToTodoActivity(
                sessionKey,
                activityId: activity.id,
                attachmentSha256: attachment.sha256,
              );
            }
          } catch (_) {
            // ignore
          }
        }
      }
    } catch (_) {
      return;
    }

    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(context.t.actions.todoNoteLink.linked(title: selected.title)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<String?> _showTodoNoteLinkSheet({
    required List<TodoLinkTarget> allTargets,
    required List<TodoLinkCandidate> ranked,
  }) async {
    final seen = <String>{};
    final candidates = <TodoLinkCandidate>[];
    for (final c in ranked) {
      candidates.add(c);
      seen.add(c.target.id);
    }
    for (final t in allTargets) {
      if (seen.contains(t.id)) continue;
      candidates.add(TodoLinkCandidate(target: t, score: 0));
    }

    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setState) {
            List<TodoLinkCandidate> filtered = candidates;
            final trimmed = query.trim();
            if (trimmed.isNotEmpty) {
              final q = trimmed.toLowerCase();
              filtered = candidates
                  .where((c) => c.target.title.toLowerCase().contains(q))
                  .toList(growable: false);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SlSurface(
                  key: const ValueKey('todo_note_link_sheet'),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t.actions.todoNoteLink.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(context.t.actions.todoNoteLink.subtitle),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('todo_note_link_search'),
                        decoration: InputDecoration(
                          hintText: context.t.common.actions.search,
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) => setState(() => query = value),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  context.t.actions.todoNoteLink.noMatches,
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final c = filtered[index];
                                  return ListTile(
                                    title: Text(c.target.title),
                                    subtitle: Text(_todoStatusLabel(
                                      context,
                                      c.target.status,
                                    )),
                                    onTap: () =>
                                        Navigator.of(context).pop(c.target.id),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _todoStatusLabel(BuildContext context, String status) =>
      switch (status) {
        'inbox' => context.t.actions.todoStatus.inbox,
        'open' => context.t.actions.todoStatus.open,
        'in_progress' => context.t.actions.todoStatus.inProgress,
        'done' => context.t.actions.todoStatus.done,
        'dismissed' => context.t.actions.todoStatus.dismissed,
        _ => status,
      };

  Future<String?> _showTodoLinkSheet({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String query,
    required List<TodoLinkTarget> targets,
    required DateTime nowLocal,
    required List<TodoLinkCandidate> ranked,
    required String defaultActionStatus,
    required bool allowAsyncRerank,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        final statusLabel = _todoStatusLabel(sheetContext, defaultActionStatus);
        final subscriptionStatus =
            SubscriptionScope.maybeOf(sheetContext)?.status ??
                SubscriptionStatus.unknown;
        final cloudAuthScope = CloudAuthScope.maybeOf(sheetContext);
        final cloudGatewayConfig =
            cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
        final showEnableCloudButton = !_cloudEmbeddingsConsented &&
            subscriptionStatus == SubscriptionStatus.entitled &&
            cloudAuthScope != null &&
            cloudGatewayConfig.baseUrl.trim().isNotEmpty;

        Future<List<TodoLinkCandidate>>? rerankFuture() {
          if (!allowAsyncRerank) return null;
          return _resolveTodoSemanticMatchesForSendFlow(
            backend,
            sessionKey,
            query: query,
            topK: 5,
          )
              .timeout(
            _kTodoLinkSheetRerankTimeout,
            onTimeout: () => const <TodoThreadMatch>[],
          )
              .then((matches) {
            if (matches.isEmpty) return ranked;
            return _mergeTodoCandidatesWithSemanticMatches(
              query: query,
              targets: targets,
              nowLocal: nowLocal,
              semanticMatches: matches,
              limit: 5,
            );
          });
        }

        Future<List<TodoLinkCandidate>?> rerankWithCloudEmbeddings() async {
          final matches = await _resolveTodoSemanticMatchesForSendFlow(
            backend,
            sessionKey,
            query: query,
            topK: 5,
            requireCloud: true,
          ).timeout(
            _kTodoLinkSheetRerankTimeout,
            onTimeout: () => const <TodoThreadMatch>[],
          );
          if (matches.isEmpty) return null;
          return _mergeTodoCandidatesWithSemanticMatches(
            query: query,
            targets: targets,
            nowLocal: nowLocal,
            semanticMatches: matches,
            limit: 5,
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _TodoLinkSheet(
              initialRanked: ranked,
              statusLabel: statusLabel,
              requestImprovedRanked: rerankFuture(),
              showEnableCloudButton: showEnableCloudButton,
              ensureCloudEmbeddingsConsented: () =>
                  _ensureEmbeddingsDataConsent(forceDialog: true),
              requestCloudRanked: rerankWithCloudEmbeddings,
              todoStatusLabel: (status) =>
                  _todoStatusLabel(sheetContext, status),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleAssistantSuggestion(
    Message sourceMessage,
    ActionSuggestion suggestion,
    int index,
  ) async {
    if (!mounted) return;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final locale = Localizations.localeOf(context);

    if (suggestion.type == 'event') {
      final settings = await ActionsSettingsStore.load();
      final timeResolution =
          (suggestion.whenText == null || suggestion.whenText!.trim().isEmpty)
              ? null
              : LocalTimeResolver.resolve(
                  suggestion.whenText!,
                  DateTime.now(),
                  locale: locale,
                  dayEndMinutes: settings.dayEndMinutes,
                );

      if (!mounted) return;
      final startLocal = await _pickEventStartTime(
        title: suggestion.title,
        timeResolution: timeResolution,
      );
      if (startLocal == null || !mounted) return;

      final startUtc = startLocal.toUtc();
      final endUtc = startLocal.add(const Duration(hours: 1)).toUtc();
      final tz = _formatTzOffset(startLocal.timeZoneOffset);
      final eventId = 'event:${sourceMessage.id}:$index';

      try {
        await CalendarAction.shareEventAsIcs(
          uid: eventId,
          title: suggestion.title,
          startUtc: startUtc,
          endUtc: endUtc,
        );
      } catch (_) {
        // ignore
      }

      try {
        await backend.upsertEvent(
          sessionKey,
          id: eventId,
          title: suggestion.title.trim(),
          startAtMs: startUtc.millisecondsSinceEpoch,
          endAtMs: endUtc.millisecondsSinceEpoch,
          tz: tz,
          sourceEntryId: sourceMessage.id,
        );
      } catch (_) {
        return;
      }

      if (!mounted) return;
      _refresh();
      return;
    }

    if (suggestion.type != 'todo') return;

    final settings = await ActionsSettingsStore.load();
    final timeResolution =
        (suggestion.whenText == null || suggestion.whenText!.trim().isEmpty)
            ? null
            : LocalTimeResolver.resolve(
                suggestion.whenText!,
                DateTime.now(),
                locale: locale,
                dayEndMinutes: settings.dayEndMinutes,
              );

    if (!mounted) return;
    final decision = await showCaptureTodoSuggestionSheet(
      context,
      title: suggestion.title,
      timeResolution: timeResolution,
    );
    if (decision == null || !mounted) return;

    final todoId = 'todo:${sourceMessage.id}:$index';

    switch (decision) {
      case CaptureTodoScheduleDecision(:final dueAtLocal):
        try {
          await backend.upsertTodo(
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
        } catch (_) {
          return;
        }
        break;
      case CaptureTodoReviewDecision():
        final nextLocal = ReviewBackoff.initialNextReviewAt(
          DateTime.now(),
          settings,
        );
        try {
          await backend.upsertTodo(
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
        } catch (_) {
          return;
        }
        break;
      case CaptureTodoNoThanksDecision():
        return;
    }

    if (!mounted) return;
    _refresh();
  }

  Future<DateTime?> _pickEventStartTime({
    required String title,
    required LocalTimeResolution? timeResolution,
  }) async {
    return showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SlSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.actions.calendar.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(title),
                  const SizedBox(height: 12),
                  Text(
                    context.t.actions.calendar.pickTime,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  if (timeResolution != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in timeResolution.candidates)
                          SlButton(
                            onPressed: () =>
                                Navigator.of(context).pop(c.dueAtLocal),
                            child: Text(c.label),
                          ),
                      ],
                    )
                  else
                    Text(
                      context.t.actions.calendar.noAutoTime,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  SlButton(
                    variant: SlButtonVariant.outline,
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: DateTime.now(),
                      );
                      if (date == null) return;
                      if (!context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(DateTime.now()),
                      );
                      if (time == null) return;
                      if (!context.mounted) return;
                      Navigator.of(context).pop(
                        DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    },
                    child: Text(context.t.actions.calendar.pickCustom),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
