part of 'chat_page.dart';

extension _ChatPageStateRuntimeSecretary on _ChatPageState {
  Future<void> _sendMessageToRuntimeSecretary(String text) async {
    final sender = widget.runtimeConversationSender ??
        SecretaryRuntimeConversationSender();
    final vaultId = _runtimeSecretaryVaultId();
    try {
      final result = await sender.send(
        vaultId: vaultId,
        conversationId: widget.conversation.id,
        message: text,
      );
      final content = result.assistantContent.trim();
      if (content.isEmpty) return;
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'assistant',
        content: content,
      );
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      if (!mounted) return;
      _refresh();
    } catch (_) {
      // During setup or tests without a runtime, keep the user message.
    }
  }

  String _runtimeSecretaryVaultId() {
    final cloudUid = CloudAuthScope.maybeOf(context)?.controller.uid?.trim();
    if (cloudUid != null && cloudUid.isNotEmpty) return cloudUid;
    return widget.conversation.id;
  }
}
