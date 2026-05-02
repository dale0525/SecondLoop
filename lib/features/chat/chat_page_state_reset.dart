part of 'chat_page.dart';

extension _ChatPageStateReset on _ChatPageState {
  String? _latestCommittedMessageId() {
    if (_latestLoadedMessages.isEmpty) return null;

    Message latest = _latestLoadedMessages.first;
    for (var i = 1; i < _latestLoadedMessages.length; i++) {
      final candidate = _latestLoadedMessages[i];
      if (candidate.createdAtMs >= latest.createdAtMs) {
        latest = candidate;
      }
    }
    return latest.id;
  }

  void _resetChatStateAfterDestructiveSyncRefresh() {
    _secretaryMemorySyncGeneration += 1;
    _paginatedMessages = <Message>[];
    _latestLoadedMessages = const <Message>[];
    _hasUnseenNewMessages = false;
    _isAtBottom = true;
    _acceptedSecretaryMemorySourceIds.clear();
    _ignoredSecretaryMemorySourceIds.clear();
    _acceptedSecretaryMemorySignatures.clear();
    _ignoredSecretaryMemorySignatures.clear();
    _persistedSecretaryMemoryProposals.clear();
    _acceptedSecretaryMemories.clear();
    _ignoredSecretaryPlanIds.clear();
    _acceptedSecretaryPlanItemIds.clear();
    _dismissedSecretaryPlanItemIds.clear();
    _lastPersistedSecretaryPlanId = null;
  }
}
