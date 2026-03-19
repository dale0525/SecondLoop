part of 'todo_detail_page.dart';

extension _TodoDetailPageStateFollowupSuggestions on _TodoDetailPageState {
  bool _supportsFollowupSuggestions() {
    final backend = AppBackendScope.maybeOf(context);
    return backend?.supportsTodoFollowupSuggestions ?? false;
  }

  Future<TodoFollowupGenerationJob?> _loadFollowupGenerationJob() async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null ||
        session == null ||
        !backend.supportsTodoFollowupSuggestions) {
      return null;
    }
    try {
      return await backend.getTodoFollowupGenerationJob(
        session.sessionKey,
        _todo.id,
      );
    } catch (_) {
      return null;
    }
  }

  bool _hasActiveFollowupGenerationJob(
    TodoFollowupGenerationJob? job,
  ) {
    if (job == null) {
      return false;
    }
    return switch (job.status) {
      // Product decision: only an in-flight job blocks another manual
      // regenerate. Failed jobs stay immediately retryable from the detail UI.
      'pending' || 'running' => true,
      _ => false,
    };
  }

  Future<bool> _prepareFollowupGeneration() async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null ||
        session == null ||
        !backend.supportsTodoFollowupSuggestions) {
      return false;
    }

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);

    final prefs = await SharedPreferences.getInstance();
    final consented =
        prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false;
    if (!consented) {
      if (!mounted) return false;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AiAskAiSettingsPage(),
        ),
      );
      return false;
    }
    final gatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final prepared = await prepareTodoFollowupGenerationRoute(
      backend,
      session.sessionKey,
      hasManualRegenerateDueJob: true,
      cloudAuthController: cloudAuthScope?.controller,
      gatewayConfig: gatewayConfig,
      subscriptionStatus: subscriptionStatus,
    );
    if (!canRunPreparedTodoFollowupGenerationRoute(prepared)) {
      if (!mounted) return false;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AiAskAiSettingsPage(),
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> _applyFollowupSuggestionIds(List<String> suggestionIds) async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    final syncEngine = SyncEngineScope.maybeOf(context);
    if (backend == null ||
        session == null ||
        !backend.supportsTodoFollowupSuggestions ||
        suggestionIds.isEmpty) {
      return;
    }

    try {
      await backend.applyTodoFollowupSuggestions(
        session.sessionKey,
        todoId: _todo.id,
        suggestionIds: suggestionIds,
      );
    } catch (error) {
      _showChecklistMutationError(error);
      return;
    }
    syncEngine?.notifyLocalMutation();
    if (!mounted) return;
    _setState(() {
      _activitiesFuture = _loadActivities();
      _followupSuggestionsFuture = _loadFollowupSuggestions();
    });
  }

  Future<void> _dismissFollowupSuggestionIds(List<String> suggestionIds) async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    final syncEngine = SyncEngineScope.maybeOf(context);
    if (backend == null ||
        session == null ||
        !backend.supportsTodoFollowupSuggestions ||
        suggestionIds.isEmpty) {
      return;
    }

    try {
      await backend.dismissTodoFollowupSuggestions(
        session.sessionKey,
        todoId: _todo.id,
        suggestionIds: suggestionIds,
      );
    } catch (error) {
      _showChecklistMutationError(error);
      return;
    }
    syncEngine?.notifyLocalMutation();
    if (!mounted) return;
    _setState(() {
      _followupSuggestionsFuture = _loadFollowupSuggestions();
    });
  }

  Future<void> _enqueueFollowupRegenerate() async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    final syncEngine = SyncEngineScope.maybeOf(context);
    if (backend == null ||
        session == null ||
        !backend.supportsTodoFollowupSuggestions ||
        _generatingFollowupSuggestions) {
      return;
    }

    _setState(() => _generatingFollowupSuggestions = true);
    try {
      final activeJob = await _loadFollowupGenerationJob();
      if (_hasActiveFollowupGenerationJob(activeJob) || !mounted) {
        return;
      }

      final ready = await _prepareFollowupGeneration();
      if (!ready || !mounted) return;

      await backend.enqueueTodoFollowupGenerationJob(
        session.sessionKey,
        todoId: _todo.id,
        triggerKind: 'manual_regenerate',
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      syncEngine?.notifyExternalChange();
      if (!mounted) return;
      _setState(() {
        _followupSuggestionsFuture = _loadFollowupSuggestions();
        _followupGenerationJobFuture = _loadFollowupGenerationJob();
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
        _setState(() => _generatingFollowupSuggestions = false);
      }
    }
  }

  Widget _buildFollowupSuggestionsSection(
    BuildContext context,
    List<TodoFollowupSuggestion> suggestions,
  ) {
    if (!_supportsFollowupSuggestions()) {
      return const SizedBox.shrink();
    }

    final pendingSuggestions = suggestions
        .where((item) => item.state == 'pending')
        .toList(growable: false);
    final appliedSuggestions = suggestions
        .where((item) => item.state == 'applied')
        .toList(growable: false);

    return FutureBuilder<TodoFollowupGenerationJob?>(
      future: _followupGenerationJobFuture ??= _loadFollowupGenerationJob(),
      builder: (context, snapshot) {
        final hasActiveGeneration =
            _hasActiveFollowupGenerationJob(snapshot.data);
        final showGeneratingIndicator =
            _generatingFollowupSuggestions || hasActiveGeneration;

        return Container(
          key: const ValueKey('todo_detail_followup_suggestions_section'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withOpacity(0.24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t.actions.todoDetail.followupSuggestionsTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  SlButton(
                    buttonKey: const ValueKey(
                      'todo_detail_followup_generate_suggestions',
                    ),
                    variant: SlButtonVariant.outline,
                    onPressed: showGeneratingIndicator
                        ? null
                        : () => unawaited(_enqueueFollowupRegenerate()),
                    child: Text(
                      suggestions.isEmpty
                          ? context.t.actions.todoDetail.followupGenerate
                          : context.t.actions.todoDetail.followupRegenerate,
                    ),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: !showGeneratingIndicator
                    ? const SizedBox.shrink()
                    : Padding(
                        key: const ValueKey(
                          'todo_detail_followup_generating_indicator',
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    context.t.actions.todoDetail
                                        .followupGenerating,
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
              if (pendingSuggestions.isEmpty && appliedSuggestions.isEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  context.t.actions.todoDetail.followupSuggestionsEmpty,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (pendingSuggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  context.t.actions.todoDetail.followupPendingTitle,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                for (final suggestion in pendingSuggestions) ...[
                  _buildFollowupSuggestionCard(context, suggestion),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SlButton(
                      buttonKey:
                          const ValueKey('todo_detail_followup_apply_pending'),
                      onPressed: () => unawaited(
                        _applyFollowupSuggestionIds(
                          pendingSuggestions
                              .map((item) => item.id)
                              .toList(growable: false),
                        ),
                      ),
                      child: Text(context.t.common.actions.apply),
                    ),
                    SlButton(
                      buttonKey: const ValueKey(
                        'todo_detail_followup_dismiss_pending',
                      ),
                      variant: SlButtonVariant.outline,
                      onPressed: () => unawaited(
                        _dismissFollowupSuggestionIds(
                          pendingSuggestions
                              .map((item) => item.id)
                              .toList(growable: false),
                        ),
                      ),
                      child: Text(
                          context.t.actions.todoDetail.checklistDismissAll),
                    ),
                  ],
                ),
              ],
              if (appliedSuggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  context.t.actions.todoDetail.followupAppliedTitle,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                for (final suggestion in appliedSuggestions) ...[
                  _buildFollowupSuggestionCard(context, suggestion),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFollowupSuggestionCard(
    BuildContext context,
    TodoFollowupSuggestion suggestion,
  ) {
    final citations = _parseTodoFollowupCitations(suggestion.citationsJson);
    final modeLabel = suggestion.generationMode ==
            TodoFollowupGenerationMode.webSearch.wireValue
        ? context.t.actions.todoDetail.followupModeWebSearch
        : context.t.actions.todoDetail.followupModeModelKnowledge;

    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  modeLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ChatMarkdownPreviewPanel(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: buildChatMarkdownPreviewBody(
              context,
              text: suggestion.content,
              selectable: true,
              bodyStyle: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          if (citations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final citation in citations)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () =>
                          unawaited(_openFollowupCitation(citation.url)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text.rich(
                          TextSpan(
                            text: citation.domain,
                            children: <InlineSpan>[
                              const TextSpan(text: ' · '),
                              TextSpan(text: citation.title),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openFollowupCitation(String rawUrl) async {
    final uri = tryParseTodoFollowupCitationUrl(rawUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<TodoFollowupCitationDraft> _parseTodoFollowupCitations(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const <TodoFollowupCitationDraft>[];

    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const <TodoFollowupCitationDraft>[];
      final out = <TodoFollowupCitationDraft>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final title = (item['title'] as String?)?.trim() ?? '';
        final url = (item['url'] as String?)?.trim() ?? '';
        final uri = tryParseTodoFollowupCitationUrl(url);
        final domain = uri?.host.trim().toLowerCase() ?? '';
        if (title.isEmpty || uri == null || domain.isEmpty) continue;
        out.add(
          TodoFollowupCitationDraft(
            title: title,
            url: uri.toString(),
            domain: domain,
          ),
        );
      }
      return out;
    } catch (_) {
      return const <TodoFollowupCitationDraft>[];
    }
  }
}
