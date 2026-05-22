part of 'agent_conversation_page.dart';

Future<RuntimeAgentState> _fetchRuntimeAgentStatePage(
  RuntimeAgentStateRepository repository, {
  required String vaultId,
  required String conversationId,
  String? turnBefore,
}) {
  final normalizedTurnBefore = turnBefore?.trim() ?? '';
  return repository.fetchAgentState(
    vaultId: vaultId,
    conversationId: conversationId,
    turnBefore: normalizedTurnBefore.isEmpty ? null : normalizedTurnBefore,
  );
}

final class _LoadEarlierRuntimeTurnsButton extends StatelessWidget {
  const _LoadEarlierRuntimeTurnsButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: TextButton(
        key: const ValueKey('agent_conversation_load_older_turns'),
        onPressed: loading ? null : () => unawaited(onPressed()),
        child: Text(context.t.chat.agentConversation.loadEarlierMessages),
      ),
    );
  }
}

mixin _AgentConversationRuntimePagination on State<AgentConversationPage> {
  Future<void> _loadOlderRuntimeTurns() async {
    final owner = this as _AgentConversationPageState;
    if (owner._loadingOlderRuntimeTurns) return;
    final turnBefore = owner._conversationTurnPage.nextBeforeTurnId.trim();
    if (turnBefore.isEmpty) return;
    setState(() => owner._loadingOlderRuntimeTurns = true);
    try {
      await owner._loadRuntimeAgentState(
        turnBefore: turnBefore,
        prependOlderTurns: true,
      );
      if (!mounted) return;
      owner._messagesFuture = Future<List<Message>>.value(
        List<Message>.from(owner._messages),
      );
    } finally {
      if (mounted) {
        setState(() => owner._loadingOlderRuntimeTurns = false);
      }
    }
  }
}
