part of 'chat_page.dart';

extension _ChatPageStateSecretary on _ChatPageState {
  SecretaryController _secretaryControllerFor(SecretaryBackend backend) {
    return SecretaryController(
      backend: backend,
      planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
    );
  }

  List<SecretaryMemoryProposal> _pendingSecretaryMemoryProposals(
    List<Message> messages,
  ) {
    final proposalsBySignature = <String, SecretaryMemoryProposal>{};
    final acceptedSignatures = <String>{
      ..._acceptedSecretaryMemorySignatures,
      for (final memory in _acceptedSecretaryMemories)
        secretaryMemoryPageSignature(memory),
    };
    for (final proposal in _persistedSecretaryMemoryProposals) {
      if (_acceptedSecretaryMemorySourceIds
          .contains(proposal.sourceMessageId)) {
        continue;
      }
      if (_ignoredSecretaryMemorySourceIds.contains(proposal.sourceMessageId)) {
        continue;
      }
      final signature = secretaryMemoryProposalSignature(proposal);
      if (acceptedSignatures.contains(signature)) continue;
      if (_ignoredSecretaryMemorySignatures.contains(signature)) continue;
      _putSecretaryMemoryProposal(proposalsBySignature, proposal);
    }
    final persistedSourceIds = proposalsBySignature.values
        .map((proposal) => proposal.sourceMessageId)
        .toSet();
    for (final message in messages) {
      if (message.role != 'user') continue;
      if (persistedSourceIds.contains(message.id)) continue;
      if (_acceptedSecretaryMemorySourceIds.contains(message.id)) continue;
      if (_ignoredSecretaryMemorySourceIds.contains(message.id)) continue;
      final proposal = _secretaryMemoryDetector.detect(
        messageId: message.id,
        text: message.content,
        createdAtMs: platformIntToInt(message.createdAtMs),
      );
      if (proposal == null) continue;
      final signature = secretaryMemoryProposalSignature(proposal);
      if (acceptedSignatures.contains(signature)) continue;
      if (_ignoredSecretaryMemorySignatures.contains(signature)) continue;
      _putSecretaryMemoryProposal(proposalsBySignature, proposal);
    }
    final proposals = proposalsBySignature.values.toList(growable: false);
    proposals.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return proposals;
  }

  void _putSecretaryMemoryProposal(
    Map<String, SecretaryMemoryProposal> proposalsBySignature,
    SecretaryMemoryProposal proposal,
  ) {
    final signature = secretaryMemoryProposalSignature(proposal);
    final existing = proposalsBySignature[signature];
    if (existing == null || proposal.createdAtMs > existing.createdAtMs) {
      proposalsBySignature[signature] = proposal;
    }
  }

  List<Widget> _buildSecretaryCards(
    List<Message> messages,
    TaskPrioritySnapshot? snapshot,
  ) {
    final cards = <Widget>[];
    final proposals = _pendingSecretaryMemoryProposals(messages);
    if (proposals.length == 1) {
      final proposal = proposals.single;
      cards.add(
        ChatSecretaryMemoryCard(
          proposal: proposal,
          onAccept: () => unawaited(_acceptSecretaryMemoryProposal(proposal)),
          onEdit: () => _openMemoryReview(proposals),
          onIgnore: () => unawaited(_ignoreSecretaryMemoryProposal(proposal)),
        ),
      );
    } else if (proposals.length > 1) {
      final first = proposals.first;
      cards.add(
        ChatSecretaryMemoryCard(
          proposal: SecretaryMemoryProposal(
            id: 'memory-proposals-summary',
            sourceMessageId: first.sourceMessageId,
            kind: 'fact',
            title: context.t.chat.secretary.memory.summaryTitle(
              count: proposals.length,
            ),
            body: context.t.chat.secretary.memory.summaryBody,
            confidence: first.confidence,
            createdAtMs: first.createdAtMs,
          ),
          onAccept: () => _openMemoryReview(proposals),
          onEdit: () => _openMemoryReview(proposals),
          onIgnore: () {
            _setState(() {
              for (final proposal in proposals) {
                _ignoredSecretaryMemorySourceIds.add(proposal.sourceMessageId);
                _ignoredSecretaryMemorySignatures.add(
                  secretaryMemoryProposalSignature(proposal),
                );
              }
            });
          },
        ),
      );
    }

    final todoCommands = _pendingSecretaryTodoCommands(messages, snapshot);
    if (todoCommands.isNotEmpty) {
      final command = todoCommands.first;
      cards.add(
        ChatSecretaryTodoCommandCard(
          command: command,
          onApply: secretaryTodoCommandCanApplyFromCard(command)
              ? () => unawaited(_applySecretaryTodoCommand(command))
              : () => _openTodoCommandReview(todoCommands),
          onReview: () => _openTodoCommandReview(todoCommands),
          onIgnore: () => _ignoreSecretaryTodoCommand(command),
        ),
      );
    }

    final plan = _secretaryPlanFromSnapshot(snapshot);
    if (plan != null && !_ignoredSecretaryPlanIds.contains(plan.id)) {
      unawaited(_persistSecretaryPlan(plan));
      cards.add(
        ChatSecretaryPlanningCard(
          plan: plan,
          onViewPlan: () => _openPlanningReview(plan),
          onRemindLater: () => _remindSecretaryPlanLater(plan),
          onIgnore: () => _ignoreSecretaryPlan(plan),
        ),
      );
    }

    return cards;
  }

  List<SecretaryTodoCommand> _pendingSecretaryTodoCommands(
    List<Message> messages,
    TaskPrioritySnapshot? snapshot,
  ) {
    if (snapshot == null || snapshot.activeEntries.isEmpty) {
      return const <SecretaryTodoCommand>[];
    }

    final targetsById = <String, TodoLinkTarget>{};
    for (final entry in snapshot.activeEntries) {
      final todo = entry.todo;
      final status = todo.status.trim();
      if (status == 'done' || status == 'dismissed') continue;
      final dueAtMs = platformIntToNullableInt(todo.dueAtMs);
      targetsById[todo.id] = TodoLinkTarget(
        id: todo.id,
        title: todo.title,
        status: status,
        dueLocal: dueAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(dueAtMs).toLocal(),
      );
    }
    if (targetsById.isEmpty) return const <SecretaryTodoCommand>[];

    final locale = Localizations.localeOf(context);
    final recentUserMessages = messages
        .where((message) => message.role == 'user')
        .toList(growable: false)
      ..sort(
        (a, b) => platformIntToInt(b.createdAtMs)
            .compareTo(platformIntToInt(a.createdAtMs)),
      );

    final commandsById = <String, SecretaryTodoCommand>{};
    for (final message in recentUserMessages.take(40)) {
      if (_appliedSecretaryTodoCommandIds.contains(message.id) ||
          _ignoredSecretaryTodoCommandIds.contains(message.id)) {
        continue;
      }

      final parsed = LocalTodoCommandParser.parse(
        messageId: message.id,
        text: message.content,
        nowLocal: DateTime.now(),
        locale: locale,
        openTodoTargets: targetsById.values.toList(growable: false),
      );
      final command = parsed.command;
      if (command == null) continue;
      if (_appliedSecretaryTodoCommandIds.contains(command.id) ||
          _ignoredSecretaryTodoCommandIds.contains(command.id)) {
        continue;
      }

      final risk = const SecretaryTodoCommandRiskPolicy().classify(command);
      if (risk != SecretaryTodoCommandRisk.review &&
          risk != SecretaryTodoCommandRisk.confirm) {
        continue;
      }
      commandsById[command.id] = command;
    }

    return commandsById.values.toList(growable: false);
  }

  SecretaryPlan? _secretaryPlanFromSnapshot(TaskPrioritySnapshot? snapshot) {
    if (snapshot == null || snapshot.isEmpty) return null;
    final plan = const RuleBasedPlanningEngine(nowLocal: DateTime.now)
        .generateDailyPlanFromPrioritySnapshot(snapshot);
    final filtered = SecretaryPlanSections(
      focus: _filterSecretaryPlanItems(plan.sections.focus),
      dueSoon: _filterSecretaryPlanItems(plan.sections.dueSoon),
      needsDecision: _filterSecretaryPlanItems(plan.sections.needsDecision),
      missingNextAction:
          _filterSecretaryPlanItems(plan.sections.missingNextAction),
    );
    if (filtered.isEmpty) return null;
    return SecretaryPlan(
      id: _secretaryPlanIdFor(filtered),
      title: plan.title,
      generatedAtMs: plan.generatedAtMs,
      route: plan.route,
      sections: filtered,
    );
  }

  List<SecretaryPlanItem> _filterSecretaryPlanItems(
    List<SecretaryPlanItem> items,
  ) {
    return items
        .where((item) =>
            !_acceptedSecretaryPlanItemIds.contains(item.id) &&
            !_dismissedSecretaryPlanItemIds.contains(item.id))
        .toList(growable: false);
  }

  String _secretaryPlanIdFor(SecretaryPlanSections sections) {
    final ids = sections.allItems.map((item) => item.id).join('|');
    return 'local-plan-$ids';
  }

  Future<void> _persistSecretaryMemoryProposalForMessage(
      Message message) async {
    final backendAny = AppBackendScope.maybeOf(context);
    if (backendAny is! SecretaryBackend) return;
    final secretaryBackend = backendAny as SecretaryBackend;
    final session = SessionScope.maybeOf(context);
    if (session == null) return;
    final controller = _secretaryControllerFor(secretaryBackend);
    final syncGeneration = _secretaryMemorySyncGeneration;
    final proposal = await controller.persistMemoryProposalForMessage(
      Uint8List.fromList(session.sessionKey),
      message,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (syncGeneration != _secretaryMemorySyncGeneration) {
      if (proposal != null) {
        await _dismissStaleSecretaryMemoryProposal(
          secretaryBackend,
          Uint8List.fromList(session.sessionKey),
          proposal,
        );
      }
      return;
    }
    if (proposal == null || !mounted) return;
    _setState(() {
      _persistedSecretaryMemoryProposals
        ..removeWhere(
          (item) =>
              item.sourceMessageId == proposal.sourceMessageId ||
              secretaryMemoryProposalSignature(item) ==
                  secretaryMemoryProposalSignature(proposal),
        )
        ..add(proposal);
    });
  }

  Future<void> _syncSecretaryMemory(
    Uint8List sessionKey,
    List<Message> messages,
  ) async {
    final backendAny = AppBackendScope.maybeOf(context);
    if (backendAny is! SecretaryBackend) return;
    final secretaryBackend = backendAny as SecretaryBackend;
    final controller = _secretaryControllerFor(secretaryBackend);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final syncGeneration = _secretaryMemorySyncGeneration;
    for (final message in messages.take(40)) {
      if (syncGeneration != _secretaryMemorySyncGeneration) return;
      final proposal = await controller.persistMemoryProposalForMessage(
        sessionKey,
        message,
        nowMs: nowMs,
      );
      if (syncGeneration != _secretaryMemorySyncGeneration) {
        if (proposal != null) {
          await _dismissStaleSecretaryMemoryProposal(
            secretaryBackend,
            sessionKey,
            proposal,
          );
        }
        return;
      }
    }
    final pending = await controller.pendingMemoryProposals(sessionKey);
    if (!mounted || syncGeneration != _secretaryMemorySyncGeneration) return;
    _setState(() {
      _persistedSecretaryMemoryProposals
        ..clear()
        ..addAll(pending);
    });
  }

  Future<void> _dismissStaleSecretaryMemoryProposal(
    SecretaryBackend backend,
    Uint8List sessionKey,
    SecretaryMemoryProposal proposal,
  ) async {
    try {
      await backend.dismissSecretaryMemoryProposal(
        sessionKey,
        proposalId: proposal.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // A stale proposal can only appear from an older async sync after reset.
      // If cleanup fails, the generation guard still prevents this page state
      // from showing it.
    }
  }

  Future<void> _acceptSecretaryMemoryProposal(
    SecretaryMemoryProposal proposal,
  ) async {
    final backendAny = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    final hasPersistedProposal = _persistedSecretaryMemoryProposals.any(
      (item) => item.id == proposal.id,
    );

    if (backendAny is SecretaryBackend &&
        session != null &&
        hasPersistedProposal) {
      final secretaryBackend = backendAny as SecretaryBackend;
      final page = await secretaryBackend.acceptSecretaryMemoryProposal(
        Uint8List.fromList(session.sessionKey),
        proposalId: proposal.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      _setState(() {
        _acceptedSecretaryMemorySourceIds.add(proposal.sourceMessageId);
        _acceptedSecretaryMemorySignatures.add(
          secretaryMemoryProposalSignature(proposal),
        );
        _persistedSecretaryMemoryProposals.removeWhere(
          (item) =>
              item.id == proposal.id ||
              secretaryMemoryProposalSignature(item) ==
                  secretaryMemoryProposalSignature(proposal),
        );
        _acceptedSecretaryMemories.add(_memoryPageFromRecord(page));
      });
      return;
    }

    _setState(() {
      _acceptedSecretaryMemorySourceIds.add(proposal.sourceMessageId);
      _acceptedSecretaryMemorySignatures.add(
        secretaryMemoryProposalSignature(proposal),
      );
      _acceptedSecretaryMemories.add(
        SecretaryMemoryPage(
          id: 'memory-${proposal.sourceMessageId}',
          title: proposal.title,
          body: proposal.body,
          state: SecretaryMemoryState.active,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          kind: proposal.kind,
          sourceMessageId: proposal.sourceMessageId,
        ),
      );
    });
  }

  Future<void> _ignoreSecretaryMemoryProposal(
    SecretaryMemoryProposal proposal,
  ) async {
    final backendAny = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    final hasPersistedProposal = _persistedSecretaryMemoryProposals.any(
      (item) => item.id == proposal.id,
    );
    if (backendAny is SecretaryBackend &&
        session != null &&
        hasPersistedProposal) {
      final secretaryBackend = backendAny as SecretaryBackend;
      await secretaryBackend.dismissSecretaryMemoryProposal(
        Uint8List.fromList(session.sessionKey),
        proposalId: proposal.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    }
    if (!mounted) return;
    _setState(() {
      _ignoredSecretaryMemorySourceIds.add(proposal.sourceMessageId);
      _ignoredSecretaryMemorySignatures.add(
        secretaryMemoryProposalSignature(proposal),
      );
      _persistedSecretaryMemoryProposals.removeWhere(
        (item) =>
            item.id == proposal.id ||
            secretaryMemoryProposalSignature(item) ==
                secretaryMemoryProposalSignature(proposal),
      );
    });
  }

  void _ignoreSecretaryPlan(SecretaryPlan plan) {
    _setState(() => _ignoredSecretaryPlanIds.add(plan.id));
  }

  void _remindSecretaryPlanLater(SecretaryPlan plan) {
    _ignoreSecretaryPlan(plan);
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(context.t.chat.secretary.planning.hiddenSnack)),
    );
  }

  Future<void> _applySecretaryTodoCommand(
    SecretaryTodoCommand command,
  ) async {
    final backend = AppBackendScope.of(context);
    final session = SessionScope.maybeOf(context);
    if (session == null) return;

    final result = await TodoCommandExecutor(
      backend: backend,
      sessionKey: Uint8List.fromList(session.sessionKey),
    ).execute(command, confirmed: true);
    if (!mounted) return;

    if (result.applied) {
      _setState(() {
        _appliedSecretaryTodoCommandIds.add(command.id);
        _appliedSecretaryTodoCommandIds.add(command.sourceMessageId);
      });
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      _refresh(refreshTaskPriority: true);
      _scaffoldMessengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(context.t.chat.secretary.todoCommand.appliedSnack),
          ),
        );
      return;
    }

    _scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(context.t.chat.secretary.todoCommand.failedSnack),
        ),
      );
  }

  void _ignoreSecretaryTodoCommand(SecretaryTodoCommand command) {
    _setState(() {
      _ignoredSecretaryTodoCommandIds.add(command.id);
      _ignoredSecretaryTodoCommandIds.add(command.sourceMessageId);
    });
  }

  Future<void> _openTodoCommandReview(
    List<SecretaryTodoCommand> commands,
  ) async {
    if (commands.isEmpty) return;
    final backend = AppBackendScope.of(context);
    final session = SessionScope.maybeOf(context);
    if (session == null) return;

    final page = TodoCommandReviewPage(
      commands: commands,
      executor: TodoCommandExecutor(
        backend: backend,
        sessionKey: Uint8List.fromList(session.sessionKey),
      ),
      onApplied: (result) {
        final command = result.command;
        _setState(() {
          _appliedSecretaryTodoCommandIds.add(command.id);
          _appliedSecretaryTodoCommandIds.add(command.sourceMessageId);
        });
        SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
        _refresh(refreshTaskPriority: true);
      },
      onIgnored: _ignoreSecretaryTodoCommand,
    );

    if (!_isDesktopPlatform &&
        MediaQuery.sizeOf(context).width < 600 &&
        commands.length == 1) {
      await _showModalBottomSheetFromChat<void>(
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) {
          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.72,
            child: page,
          );
        },
      );
      return;
    }

    await _pushRouteFromChat(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(context, page),
      ),
    );
  }

  Future<void> _openMemoryReview([
    List<SecretaryMemoryProposal>? proposals,
  ]) async {
    final pending = proposals ??
        _pendingSecretaryMemoryProposals(_latestLoadedMessages).toList();
    await _pushRouteFromChat(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          MemoryReviewPage(
            pending: pending,
            current: _acceptedSecretaryMemories,
            onAcceptProposal: (proposal) =>
                unawaited(_acceptSecretaryMemoryProposal(proposal)),
            onDismissProposal: (proposal) =>
                unawaited(_ignoreSecretaryMemoryProposal(proposal)),
          ),
        ),
      ),
    );
  }

  Future<void> _openPlanningReview(SecretaryPlan plan) async {
    final page = PlanningReviewPage(
      plan: plan,
      onAcceptSuggestion: (itemId) {
        _setState(() => _acceptedSecretaryPlanItemIds.add(itemId));
      },
      onDismissSuggestion: (itemId) {
        _setState(() => _dismissedSecretaryPlanItemIds.add(itemId));
      },
    );

    if (!_isDesktopPlatform && MediaQuery.sizeOf(context).width < 600) {
      await _showModalBottomSheetFromChat<void>(
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) {
          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.86,
            child: page,
          );
        },
      );
      return;
    }

    await _pushRouteFromChat(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(context, page),
      ),
    );
  }

  Widget _buildSecretaryCardListItem(Widget card) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: card,
    );
  }

  SecretaryMemoryPage _memoryPageFromRecord(MemoryPageRecord record) {
    return SecretaryMemoryPage(
      id: record.pageId,
      title: record.title,
      body: record.body,
      state: switch (record.state) {
        'archived' => SecretaryMemoryState.archived,
        'stale' || 'needs_review' => SecretaryMemoryState.needsReview,
        _ => SecretaryMemoryState.active,
      },
      updatedAtMs: platformIntToInt(record.updatedAtMs),
      kind: record.pageType,
    );
  }

  Future<void> _persistSecretaryPlan(SecretaryPlan plan) async {
    if (_lastPersistedSecretaryPlanId == plan.id) return;
    final backendAny = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backendAny is! SecretaryBackend || session == null) return;
    final secretaryBackend = backendAny as SecretaryBackend;
    _lastPersistedSecretaryPlanId = plan.id;
    await secretaryBackend.upsertPlanningOutput(
      Uint8List.fromList(session.sessionKey),
      id: plan.id,
      kind: 'daily_plan',
      title: plan.title,
      body: _secretaryPlanSummaryText(plan, trailingPeriod: true),
      itemsJson: _secretaryPlanItemsJson(plan),
      sourceRefsJson: jsonEncode({
        'todo_ids': [for (final item in plan.sections.allItems) item.todoId],
      }),
      route: plan.route,
      state: 'active',
      createdAtMs: plan.generatedAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      expiresAtMs:
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
  }

  String _secretaryPlanSummaryText(
    SecretaryPlan plan, {
    bool trailingPeriod = false,
  }) {
    final t = context.t.chat.secretary.planning;
    final suggestions = plan.itemCount == 1
        ? t.oneSuggestion
        : t.manySuggestions(count: plan.itemCount);
    final confirmations = plan.requiresConfirmationCount == 1
        ? t.oneNeedsConfirmation
        : t.manyNeedConfirmation(count: plan.requiresConfirmationCount);
    if (trailingPeriod) {
      return t.persistedBody(
        suggestions: suggestions,
        confirmations: confirmations,
      );
    }
    return t.summary(
      suggestions: suggestions,
      confirmations: confirmations,
    );
  }

  String _secretaryPlanItemsJson(SecretaryPlan plan) {
    final items = <Map<String, Object?>>[];
    void add(String section, List<SecretaryPlanItem> sectionItems) {
      for (final item in sectionItems) {
        items.add({
          'id': item.id,
          'todo_id': item.todoId,
          'section': section,
          'title': item.title,
          'reason': item.reason,
          'due_at_ms': item.dueAtMs,
          'requires_confirmation': item.requiresConfirmation,
        });
      }
    }

    add('focus', plan.sections.focus);
    add('due_soon', plan.sections.dueSoon);
    add('needs_decision', plan.sections.needsDecision);
    add('missing_next_action', plan.sections.missingNextAction);
    return jsonEncode(items);
  }
}
