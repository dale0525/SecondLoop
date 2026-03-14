part of 'todo_detail_page.dart';

extension _TodoDetailPageStateChecklistSuggestions on _TodoDetailPageState {
  Future<void> _applyChecklistSuggestionIds(List<String> suggestionIds) async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null || suggestionIds.isEmpty) {
      return;
    }

    await backend.applyTodoChecklistSuggestions(
      session.sessionKey,
      todoId: _todo.id,
      suggestionIds: suggestionIds,
    );
    if (!mounted) return;
    _setState(() {
      _selectedChecklistSuggestionIds.removeAll(suggestionIds);
      _checklistFuture = _loadChecklistItems();
      _checklistSuggestionsFuture = _loadChecklistSuggestions();
    });
  }

  Future<void> _dismissChecklistSuggestionIds(
      List<String> suggestionIds) async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null || suggestionIds.isEmpty) {
      return;
    }

    await backend.dismissTodoChecklistSuggestions(
      session.sessionKey,
      todoId: _todo.id,
      suggestionIds: suggestionIds,
    );
    if (!mounted) return;
    _setState(() {
      _selectedChecklistSuggestionIds.removeAll(suggestionIds);
      _checklistSuggestionsFuture = _loadChecklistSuggestions();
    });
  }

  Future<void> _applySelectedChecklistSuggestions() {
    return _applyChecklistSuggestionIds(
      _selectedChecklistSuggestionIds.toList(growable: false),
    );
  }

  Future<void> _dismissSelectedChecklistSuggestions() {
    return _dismissChecklistSuggestionIds(
      _selectedChecklistSuggestionIds.toList(growable: false),
    );
  }

  Future<void> _dismissAllChecklistSuggestions() async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null) return;

    await backend.dismissAllTodoChecklistSuggestions(
      session.sessionKey,
      todoId: _todo.id,
    );
    if (!mounted) return;
    _setState(() {
      _selectedChecklistSuggestionIds.clear();
      _checklistSuggestionsFuture = _loadChecklistSuggestions();
    });
  }

  Future<void> _generateChecklistSuggestions() async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null || _generatingChecklistSuggestions) {
      return;
    }

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final gatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    _setState(() => _generatingChecklistSuggestions = true);

    try {
      final cloudIdToken = await readCloudCapabilityIdToken(
        cloudAuthScope?.controller,
        mode: CloudCapabilityAuthMode.interactive,
      );
      final route = await decideAskAiRoute(
        backend,
        session.sessionKey,
        cloudIdToken: cloudIdToken,
        cloudGatewayBaseUrl: gatewayConfig.baseUrl,
        subscriptionStatus: subscriptionStatus,
      );

      if (route == AskAiRouteKind.needsSetup) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AiAskAiSettingsPage(),
          ),
        );
        return;
      }

      if (route == AskAiRouteKind.cloudGateway) {
        await bestEffortWarmCloudCapabilityAuth(cloudAuthScope?.controller);
      }

      final activities = await backend.listTodoActivities(
        session.sessionKey,
        _todo.id,
      );
      final contextText = buildTodoChecklistSuggestionContext(
        todo: _todo,
        activities: activities,
      );
      final suggestions = await requestTodoChecklistSuggestions(
        backend: backend,
        sessionKey: session.sessionKey,
        route: route,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        idToken: cloudIdToken ?? '',
        modelName: gatewayConfig.modelName,
        taskTitle: _todo.title,
        taskContext: contextText,
        localeTag: localeTag,
        status: _todo.status,
        dueAtMs: _todo.dueAtMs?.toInt(),
      );
      if (suggestions.isNotEmpty) {
        await backend.upsertGeneratedTodoChecklistSuggestions(
          session.sessionKey,
          todoId: _todo.id,
          suggestions: suggestions,
          source: route == AskAiRouteKind.cloudGateway ? 'cloud' : 'byok',
          generationKey: 'manual:${DateTime.now().millisecondsSinceEpoch}',
        );
      }
      if (!mounted) return;
      _setState(() {
        _selectedChecklistSuggestionIds.clear();
        _checklistSuggestionsFuture = _loadChecklistSuggestions();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$error')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        _setState(() => _generatingChecklistSuggestions = false);
      }
    }
  }

  Widget _buildChecklistSuggestionsSection(
    BuildContext context,
    List<TodoChecklistSuggestion> suggestions,
  ) {
    final pendingSuggestions = suggestions
        .where((item) => item.state == 'pending')
        .toList(growable: false);
    final pendingSuggestionIds =
        pendingSuggestions.map((item) => item.id).toList(growable: false);
    final hasSelection = _selectedChecklistSuggestionIds.isNotEmpty;

    return Container(
      key: const ValueKey('todo_detail_checklist_suggestions_section'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t.actions.todoDetail.checklistSuggestionsTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              SlButton(
                buttonKey: const ValueKey(
                    'todo_detail_checklist_generate_suggestions'),
                variant: SlButtonVariant.outline,
                onPressed: _generatingChecklistSuggestions
                    ? null
                    : () => unawaited(_generateChecklistSuggestions()),
                child: Text(
                  suggestions.isEmpty
                      ? context.t.actions.todoDetail.checklistGenerate
                      : context.t.actions.todoDetail.checklistRegenerate,
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: !_generatingChecklistSuggestions
                ? const SizedBox.shrink()
                : Padding(
                    key: const ValueKey(
                      'todo_detail_checklist_generating_indicator',
                    ),
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context
                                    .t.actions.todoDetail.checklistGenerating,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(minHeight: 3),
                      ],
                    ),
                  ),
          ),
          if (pendingSuggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final suggestion in pendingSuggestions)
              Row(
                children: [
                  Checkbox(
                    key: ValueKey(
                      'todo_detail_checklist_suggestion_select_${suggestion.id}',
                    ),
                    value:
                        _selectedChecklistSuggestionIds.contains(suggestion.id),
                    onChanged: (value) {
                      _setState(() {
                        if (value ?? false) {
                          _selectedChecklistSuggestionIds.add(suggestion.id);
                        } else {
                          _selectedChecklistSuggestionIds.remove(suggestion.id);
                        }
                      });
                    },
                  ),
                  Expanded(child: Text(suggestion.content)),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SlButton(
                  buttonKey:
                      const ValueKey('todo_detail_checklist_apply_selected'),
                  onPressed: hasSelection
                      ? () => unawaited(_applySelectedChecklistSuggestions())
                      : null,
                  child: Text(context.t.common.actions.apply),
                ),
                SlButton(
                  buttonKey:
                      const ValueKey('todo_detail_checklist_dismiss_selected'),
                  variant: SlButtonVariant.outline,
                  onPressed: hasSelection
                      ? () => unawaited(_dismissSelectedChecklistSuggestions())
                      : null,
                  child: Text(
                    context.t.actions.todoDetail.checklistDismissSelected,
                  ),
                ),
                SlButton(
                  buttonKey: const ValueKey('todo_detail_checklist_apply_all'),
                  variant: SlButtonVariant.outline,
                  onPressed: pendingSuggestionIds.isEmpty
                      ? null
                      : () => unawaited(
                            _applyChecklistSuggestionIds(pendingSuggestionIds),
                          ),
                  child: Text(context.t.actions.todoDetail.checklistApplyAll),
                ),
                SlButton(
                  buttonKey:
                      const ValueKey('todo_detail_checklist_dismiss_all'),
                  variant: SlButtonVariant.outline,
                  onPressed: pendingSuggestionIds.isEmpty
                      ? null
                      : () => unawaited(
                            _dismissAllChecklistSuggestions(),
                          ),
                  child: Text(
                    context.t.actions.todoDetail.checklistDismissAll,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
