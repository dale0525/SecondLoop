part of 'chat_page.dart';

extension _ChatPageStateRuntimeSecretary on _ChatPageState {
  Future<void> _sendMessageToRuntimeSecretary(
    String text, {
    String? sourceMessageId,
  }) async {
    _setState(() => _runtimeSecretaryRunning = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final conversationId = widget.conversation.id;
      await _warmRuntimeSecretaryHostedAuthIfNeeded();
      if (!mounted) return;
      final sender = _runtimeSecretaryConversationSender();
      final vaultId = _runtimeSecretaryVaultId();
      final result = await RuntimeSecretaryAppService(
        sender: sender,
        backend: backend,
        sessionKey: sessionKey,
      )
          .sendAndApply(
            vaultId: vaultId,
            conversationId: conversationId,
            message: text,
            sourceMessageId: sourceMessageId,
          )
          .timeout(_kRuntimeSecretaryRequestTimeout);
      if (!mounted) return;
      final syncEngine = SyncEngineScope.maybeOf(context);
      syncEngine?.notifyLocalMutation();
      if (result.metadata.appliedMutations.isNotEmpty) {
        syncEngine?.triggerPullNow();
      }
      _refresh();
    } catch (_) {
      if (!mounted) return;
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(context.t.chat.askAiFailedTemporary),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        _setState(() => _runtimeSecretaryRunning = false);
      }
    }
  }

  ChatRuntimeConversationSender _runtimeSecretaryConversationSender() {
    final injected = widget.runtimeConversationSender;
    if (injected != null) return injected;

    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final gatewayBaseUrl = cloudAuthScope?.gatewayConfig.baseUrl.trim() ?? '';
    if (cloudAuthScope != null && gatewayBaseUrl.isNotEmpty) {
      return SecretaryRuntimeConversationSender.hostedManagedPro(
        apiBaseUrl: gatewayBaseUrl,
        hostedSessionTokenGetter: () => readCloudCapabilityIdToken(
          cloudAuthScope.controller,
          mode: CloudCapabilityAuthMode.interactive,
        ),
      );
    }

    return SecretaryRuntimeConversationSender();
  }

  Future<void> _warmRuntimeSecretaryHostedAuthIfNeeded() async {
    if (widget.runtimeConversationSender != null) return;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    if (cloudAuthScope == null) return;
    if (cloudAuthScope.gatewayConfig.baseUrl.trim().isEmpty) return;
    if ((cloudAuthScope.controller.uid ?? '').trim().isNotEmpty) return;
    await readCloudCapabilityIdToken(
      cloudAuthScope.controller,
      mode: CloudCapabilityAuthMode.interactive,
    );
  }

  String _runtimeSecretaryVaultId() {
    final cloudUid = CloudAuthScope.maybeOf(context)?.controller.uid?.trim();
    if (cloudUid != null && cloudUid.isNotEmpty) return cloudUid;
    return widget.conversation.id;
  }
}
