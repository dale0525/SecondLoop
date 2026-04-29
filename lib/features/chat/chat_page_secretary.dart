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
    final proposals = <SecretaryMemoryProposal>[
      for (final proposal in _persistedSecretaryMemoryProposals)
        if (!_acceptedSecretaryMemorySourceIds
                .contains(proposal.sourceMessageId) &&
            !_ignoredSecretaryMemorySourceIds
                .contains(proposal.sourceMessageId))
          proposal,
    ];
    final persistedSourceIds =
        proposals.map((proposal) => proposal.sourceMessageId).toSet();
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
      if (proposal != null) proposals.add(proposal);
    }
    proposals.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return proposals;
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
            title: '${proposals.length} memory suggestions',
            body: 'Review suggested memory updates before saving them.',
            confidence: first.confidence,
            createdAtMs: first.createdAtMs,
          ),
          onAccept: () => _openMemoryReview(proposals),
          onEdit: () => _openMemoryReview(proposals),
          onIgnore: () {
            _setState(() {
              for (final proposal in proposals) {
                _ignoredSecretaryMemorySourceIds.add(proposal.sourceMessageId);
              }
            });
          },
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

  SecretaryPlan? _secretaryPlanFromSnapshot(TaskPrioritySnapshot? snapshot) {
    if (snapshot == null || snapshot.isEmpty) return null;
    final todos = [
      for (final entry in snapshot.activeEntries) entry.todo,
    ];
    final plan = const RuleBasedPlanningEngine(nowLocal: DateTime.now)
        .generateDailyPlan(todos);
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
    final proposal = await controller.persistMemoryProposalForMessage(
      Uint8List.fromList(session.sessionKey),
      message,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (proposal == null || !mounted) return;
    _setState(() {
      _persistedSecretaryMemoryProposals
        ..removeWhere(
            (item) => item.sourceMessageId == proposal.sourceMessageId)
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
    for (final message in messages.take(40)) {
      await controller.persistMemoryProposalForMessage(
        sessionKey,
        message,
        nowMs: nowMs,
      );
    }
    final pending = await controller.pendingMemoryProposals(sessionKey);
    if (!mounted) return;
    _setState(() {
      _persistedSecretaryMemoryProposals
        ..clear()
        ..addAll(pending);
    });
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
        _persistedSecretaryMemoryProposals.removeWhere(
          (item) => item.id == proposal.id,
        );
        _acceptedSecretaryMemories.add(_memoryPageFromRecord(page));
      });
      return;
    }

    _setState(() {
      _acceptedSecretaryMemorySourceIds.add(proposal.sourceMessageId);
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
      _persistedSecretaryMemoryProposals.removeWhere(
        (item) => item.id == proposal.id,
      );
    });
  }

  void _ignoreSecretaryPlan(SecretaryPlan plan) {
    _setState(() => _ignoredSecretaryPlanIds.add(plan.id));
  }

  void _remindSecretaryPlanLater(SecretaryPlan plan) {
    _ignoreSecretaryPlan(plan);
    _scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Plan hidden for now.')),
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
      body: '${plan.itemCount} suggestions, '
          '${plan.requiresConfirmationCount} need confirmation.',
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
