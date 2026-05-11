part of 'chat_page.dart';

extension _ChatPageStateRuntimeSecretary on _ChatPageState {
  Future<void> _sendMessageToRuntimeSecretary(
    String text, {
    String? sourceMessageId,
  }) async {
    _setState(() => _runtimeSecretaryRunning = true);
    try {
      await _warmRuntimeSecretaryHostedAuthIfNeeded();
      final sender = _runtimeSecretaryConversationSender();
      final vaultId = _runtimeSecretaryVaultId();
      final result = await sender
          .send(
            vaultId: vaultId,
            conversationId: widget.conversation.id,
            message: text,
          )
          .timeout(_kRuntimeSecretaryRequestTimeout);
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
      await _applyRuntimeTaskCreations(
        result,
        backend: backend,
        sessionKey: sessionKey,
        sourceMessageId: sourceMessageId,
      );
      final syncEngine = SyncEngineScope.maybeOf(context);
      syncEngine?.notifyLocalMutation();
      if (result.metadata.appliedMutations.isNotEmpty) {
        syncEngine?.triggerPullNow();
      }
      if (!mounted) return;
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

  Future<void> _applyRuntimeTaskCreations(
    SecretaryRuntimeConversationResult result, {
    required AppBackend backend,
    required Uint8List sessionKey,
    required String? sourceMessageId,
  }) async {
    for (final mutation in result.metadata.appliedMutations) {
      if (_runtimeString(mutation['entity_type']) != 'task') continue;
      if (_runtimeString(mutation['mutation_type']) != 'create') continue;
      if (_runtimeString(mutation['status']) != 'applied') continue;

      final record = _runtimeMap(mutation['record']);
      final id = _runtimeString(record['id']) ??
          _runtimeString(record['task_id']) ??
          _runtimeString(mutation['record_id']);
      final title = _runtimeString(record['title']);
      if (id == null || title == null) continue;

      await backend.upsertTodo(
        sessionKey,
        id: id,
        title: title,
        dueAtMs:
            _runtimeInt(record['due_at_ms']) ?? _runtimeInt(record['dueAtMs']),
        status: _runtimeTodoStatus(record['status']),
        sourceEntryId: sourceMessageId,
        reviewStage: _runtimeInt(record['review_stage']) ??
            _runtimeInt(record['reviewStage']),
        nextReviewAtMs: _runtimeInt(record['next_review_at_ms']) ??
            _runtimeInt(record['nextReviewAtMs']),
        lastReviewAtMs: _runtimeInt(record['last_review_at_ms']) ??
            _runtimeInt(record['lastReviewAtMs']),
      );
    }
  }

  Map<String, Object?> _runtimeMap(Object? raw) {
    if (raw is! Map) return const <String, Object?>{};
    return raw.map((key, value) => MapEntry('$key', value as Object?));
  }

  String? _runtimeString(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _runtimeInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String _runtimeTodoStatus(Object? raw) {
    final status = _runtimeString(raw)?.toLowerCase();
    if (status == null ||
        status == 'todo' ||
        status == 'to_do' ||
        status == 'pending' ||
        status == 'not_started') {
      return 'open';
    }
    return status;
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
