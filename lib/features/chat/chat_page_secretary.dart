part of 'chat_page.dart';

extension _ChatPageStateSecretary on _ChatPageState {
  List<SecretaryMemoryProposal> _pendingSecretaryMemoryProposals(
    List<Message> messages,
  ) {
    final proposals = <SecretaryMemoryProposal>[];
    for (final message in messages) {
      if (message.role != 'user') continue;
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
          onAccept: () => _acceptSecretaryMemoryProposal(proposal),
          onEdit: () => _openMemoryReview(proposals),
          onIgnore: () => _ignoreSecretaryMemoryProposal(proposal),
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

  void _acceptSecretaryMemoryProposal(SecretaryMemoryProposal proposal) {
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

  void _ignoreSecretaryMemoryProposal(SecretaryMemoryProposal proposal) {
    _setState(() {
      _ignoredSecretaryMemorySourceIds.add(proposal.sourceMessageId);
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
            onAcceptProposal: _acceptSecretaryMemoryProposal,
            onDismissProposal: _ignoreSecretaryMemoryProposal,
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
}
