part of 'chat_page.dart';

extension _ChatPageStateMethodsC on _ChatPageState {
  Future<void> _handleMessageAutoActions(
      Message message, String rawText) async {
    if (!mounted) return;

    final locale = Localizations.localeOf(context);
    final trimmedText = rawText.trim();
    final forceTodoSelectionPrompt =
        _looksLikeBareTodoStatusUpdate(trimmedText);
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final settingsFuture = ActionsSettingsStore.load();
    final todosFuture =
        Future<List<Todo>>.sync(() => backend.listTodos(sessionKey))
            .catchError((_) => const <Todo>[]);

    final settings = await settingsFuture;
    if (!mounted) return;
    final todos = await todosFuture;

    final nowLocal = DateTime.now();
    final timeResolution = LocalTimeResolver.resolve(
      rawText,
      nowLocal,
      locale: locale,
      dayEndMinutes: settings.dayEndMinutes,
    );
    final looksLikeReview = LocalTimeResolver.looksLikeReviewIntent(rawText);
    final targets = <TodoLinkTarget>[];
    final todosById = <String, Todo>{};
    for (final todo in todos) {
      if (todo.status == 'done' || todo.status == 'dismissed') continue;
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

    var semanticMatches = const <TodoThreadMatch>[];
    var semanticTimedOut = false;
    if (targets.isNotEmpty && timeResolution == null && !looksLikeReview) {
      try {
        semanticMatches = await _resolveTodoSemanticMatchesForSendFlow(
          backend,
          sessionKey,
          query: rawText,
          topK: 5,
        ).timeout(
          _kTodoAutoSemanticTimeout,
          onTimeout: () {
            semanticTimedOut = true;
            return const <TodoThreadMatch>[];
          },
        );
      } catch (_) {
        semanticMatches = const <TodoThreadMatch>[];
        semanticTimedOut = true;
      }
    }

    if (!mounted) return;
    final firstDayOfWeekIndex =
        MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final looksLikeLongFormNote =
        trimmedText.contains('\n') || trimmedText.runes.length >= 240;
    final looksLikeTodoRelevant = _looksLikeTodoRelevantForAi(trimmedText);

    if (!forceTodoSelectionPrompt &&
        !looksLikeReview &&
        !looksLikeLongFormNote &&
        looksLikeTodoRelevant) {
      final prefs = await SharedPreferences.getInstance();
      final consented =
          prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false;
      if (consented && mounted) {
        String? cloudIdToken;
        try {
          cloudIdToken = await cloudAuthScope?.controller.getIdToken();
        } catch (_) {
          cloudIdToken = null;
        }

        AskAiRouteKind route;
        try {
          route = await decideAiAutomationRoute(
            backend,
            sessionKey,
            cloudIdToken: cloudIdToken,
            cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
            subscriptionStatus: subscriptionStatus,
          );
        } catch (_) {
          route = AskAiRouteKind.needsSetup;
        }

        if (route != AskAiRouteKind.needsSetup) {
          try {
            await backend.enqueueSemanticParseJob(
              sessionKey,
              messageId: message.id,
              nowMs: DateTime.now().millisecondsSinceEpoch,
            );
            if (mounted) _setState(() {});
            syncEngine?.notifyExternalChange();
            return;
          } catch (_) {
            // Fall through to local resolver.
          }
        }
      }
    }

    var decision = MessageActionResolver.resolve(
      rawText,
      locale: locale,
      nowLocal: nowLocal,
      dayEndMinutes: settings.dayEndMinutes,
      morningMinutes: settings.morningMinutes,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
      openTodoTargets: targets,
      semanticMatches: semanticMatches,
    );

    if (forceTodoSelectionPrompt && decision is MessageActionFollowUpDecision) {
      // For status-only messages like "done"/"完成", always ask which todo to
      // update instead of auto-applying a semantic match.
      decision = const MessageActionNoneDecision();
    }

    switch (decision) {
      case MessageActionFollowUpDecision(:final todoId, :final newStatus):
        final selected = todosById[todoId];
        if (selected == null) return;

        final previousStatus = selected.status;
        try {
          await backend.setTodoStatus(
            sessionKey,
            todoId: selected.id,
            newStatus: newStatus,
            sourceMessageId: message.id,
          );
          syncEngine?.notifyLocalMutation();
        } catch (_) {
          return;
        }

        try {
          final activity = await backend.appendTodoNote(
            sessionKey,
            todoId: selected.id,
            content: rawText.trim(),
            sourceMessageId: message.id,
          );
          final attachmentsBackend = backend is AttachmentsBackend
              ? backend as AttachmentsBackend
              : null;
          if (attachmentsBackend != null) {
            final attachments = await attachmentsBackend.listMessageAttachments(
              sessionKey,
              message.id,
            );
            for (final attachment in attachments) {
              await backend.linkAttachmentToTodoActivity(
                sessionKey,
                activityId: activity.id,
                attachmentSha256: attachment.sha256,
              );
            }
          }
        } catch (_) {
          // ignore
        }

        if (!mounted) return;
        _refresh();

        final snackText = context.t.actions.todoLink.updated(
          title: selected.title,
          status: _todoStatusLabel(context, newStatus),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackText),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: context.t.common.actions.undo,
              onPressed: () async {
                try {
                  await backend.setTodoStatus(
                    sessionKey,
                    todoId: selected.id,
                    newStatus: previousStatus,
                  );
                  syncEngine?.notifyLocalMutation();
                } catch (_) {
                  return;
                }
                if (!mounted) return;
                _refresh();
              },
            ),
          ),
        );
        return;
      case MessageActionCreateDecision(
          :final title,
          :final status,
          :final dueAtLocal,
          :final recurrenceRule,
        ):
        final todoId = 'todo:${message.id}';
        int? reviewStage;
        int? nextReviewAtMs;
        if (dueAtLocal == null && status != 'done' && status != 'dismissed') {
          final nextLocal = ReviewBackoff.initialNextReviewAt(
            DateTime.now(),
            settings,
          );
          reviewStage = 0;
          nextReviewAtMs = nextLocal.toUtc().millisecondsSinceEpoch;
        }
        try {
          await backend.upsertTodo(
            sessionKey,
            id: todoId,
            title: title,
            dueAtMs: dueAtLocal?.toUtc().millisecondsSinceEpoch,
            status: status,
            sourceEntryId: message.id,
            reviewStage: reviewStage,
            nextReviewAtMs: nextReviewAtMs,
            lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
          final recurrenceRuleJson = recurrenceRule?.toJsonString();
          if (recurrenceRuleJson != null && recurrenceRuleJson.isNotEmpty) {
            await backend.upsertTodoRecurrence(
              sessionKey,
              todoId: todoId,
              seriesId: 'series:${message.id}',
              ruleJson: recurrenceRuleJson,
            );
          }
          syncEngine?.notifyLocalMutation();
        } catch (_) {
          return;
        }

        if (!mounted) return;
        _refresh();

        final snackText = context.t.actions.todoAuto.created(title: title);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackText),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: context.t.common.actions.undo,
              onPressed: () async {
                try {
                  await backend.deleteTodo(sessionKey, todoId: todoId);
                  syncEngine?.notifyLocalMutation();
                } catch (_) {
                  return;
                }
                if (!mounted) return;
                _refresh();
              },
            ),
          ),
        );
        return;
      case MessageActionNoneDecision():
        break;
    }

    // Fallback: keep legacy prompts for non-auto cases.
    if (timeResolution != null || looksLikeReview) {
      if (!mounted) return;
      final decision = await showCaptureTodoSuggestionSheet(
        context,
        title: rawText.trim(),
        timeResolution: timeResolution,
      );
      if (decision == null || !mounted) return;

      final todoId = 'todo:${message.id}';
      switch (decision) {
        case CaptureTodoScheduleDecision(:final dueAtLocal):
          try {
            await backend.upsertTodo(
              sessionKey,
              id: todoId,
              title: rawText.trim(),
              dueAtMs: dueAtLocal.toUtc().millisecondsSinceEpoch,
              status: 'open',
              sourceEntryId: message.id,
              reviewStage: null,
              nextReviewAtMs: null,
              lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            );
            syncEngine?.notifyLocalMutation();
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
              title: rawText.trim(),
              dueAtMs: null,
              status: 'inbox',
              sourceEntryId: message.id,
              reviewStage: 0,
              nextReviewAtMs: nextLocal.toUtc().millisecondsSinceEpoch,
              lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            );
            syncEngine?.notifyLocalMutation();
          } catch (_) {
            return;
          }
          break;
        case CaptureTodoNoThanksDecision():
          return;
      }

      if (!mounted) return;
      _refresh();
      return;
    }

    if (targets.isEmpty) return;

    final intent = inferTodoUpdateIntent(rawText);
    final ranked = _mergeTodoCandidatesWithSemanticMatches(
      query: rawText,
      targets: targets,
      nowLocal: nowLocal,
      semanticMatches: semanticMatches,
      limit: 5,
    );
    if (ranked.isEmpty) return;

    final top = ranked[0];
    final secondScore = ranked.length > 1 ? ranked[1].score : 0;
    final isHighConfidence = top.score >= 3200 ||
        (top.score >= 2400 && (top.score - secondScore) >= 900);
    final shouldPrompt = intent.isExplicit || top.score >= 1600;
    if (!shouldPrompt) {
      final looksLikeLongFormNote =
          rawText.contains('\n') || rawText.trim().runes.length >= 160;
      if (looksLikeLongFormNote && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.actions.todoNoteLink.suggest),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: context.t.actions.todoNoteLink.actionShort,
              onPressed: () => unawaited(_linkMessageToTodo(message)),
            ),
          ),
        );
      }
      return;
    }

    final selectedTodoId = (isHighConfidence && !forceTodoSelectionPrompt)
        ? top.target.id
        : await _showTodoLinkSheet(
            backend: backend,
            sessionKey: sessionKey,
            query: rawText,
            targets: targets,
            nowLocal: nowLocal,
            ranked: ranked,
            defaultActionStatus: intent.newStatus,
            allowAsyncRerank: semanticTimedOut,
          );
    if (selectedTodoId == null || !mounted) return;

    final selected = todosById[selectedTodoId];
    if (selected == null) return;

    final previousStatus = selected.status;

    try {
      await backend.setTodoStatus(
        sessionKey,
        todoId: selected.id,
        newStatus: intent.newStatus,
        sourceMessageId: message.id,
      );
      syncEngine?.notifyLocalMutation();
    } catch (_) {
      return;
    }

    try {
      final activity = await backend.appendTodoNote(
        sessionKey,
        todoId: selected.id,
        content: rawText.trim(),
        sourceMessageId: message.id,
      );
      final attachmentsBackend =
          backend is AttachmentsBackend ? backend as AttachmentsBackend : null;
      if (attachmentsBackend != null) {
        final attachments = await attachmentsBackend.listMessageAttachments(
            sessionKey, message.id);
        for (final attachment in attachments) {
          await backend.linkAttachmentToTodoActivity(
            sessionKey,
            activityId: activity.id,
            attachmentSha256: attachment.sha256,
          );
        }
      }
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    _refresh();

    final snackText = context.t.actions.todoLink.updated(
      title: selected.title,
      status: _todoStatusLabel(context, intent.newStatus),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackText),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: context.t.common.actions.undo,
          onPressed: () async {
            try {
              await backend.setTodoStatus(
                sessionKey,
                todoId: selected.id,
                newStatus: previousStatus,
              );
              syncEngine?.notifyLocalMutation();
            } catch (_) {
              return;
            }
            if (!mounted) return;
            _refresh();
          },
        ),
      ),
    );
  }
}
