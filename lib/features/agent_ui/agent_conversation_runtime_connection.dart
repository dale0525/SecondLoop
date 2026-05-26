part of 'agent_conversation_page.dart';

extension _AgentConversationRuntimeConnection on _AgentConversationPageState {
  void _ensureRuntimeConnectionLoaded() {
    if (RuntimeConnectionStore.cachePrimed ||
        _runtimeConnectionLoadFuture != null) {
      return;
    }
    _runtimeConnectionLoadFuture = RuntimeConnectionStore()
        .loadConnection()
        .then<CloudRuntimeConnection?>((connection) {
      if (!mounted) return connection;
      if (_usesRuntimeAgentState && _runtimeAgentStateFuture == null) {
        _activateRuntimeStateAfterConnectionLoad();
      } else {
        _rebuildAfterRuntimeConnectionLoad();
      }
      return connection;
    }).catchError((_) => null);
  }

  CloudRuntimeConnection? get _selfManagedRuntimeConnection {
    final connection = RuntimeConnectionStore.cachedConnection;
    if (connection?.profile.runtimeMode != CloudRuntimeMode.selfManaged) {
      return null;
    }
    return connection;
  }

  String _activeRuntimeVaultId() {
    final selfManagedVaultId =
        _selfManagedRuntimeConnection?.profile.vaultId.trim() ?? '';
    if (selfManagedVaultId.isNotEmpty) return selfManagedVaultId;
    return CloudAuthScope.maybeOf(context)?.controller.uid?.trim() ?? '';
  }

  bool get _usesRuntimeAgentState {
    if (_activeRuntimeVaultId().isEmpty) return false;
    return _selfManagedRuntimeConnection != null ||
        widget.runtimeAgentStateRepository != null ||
        widget.runtimeConversationSender == null;
  }

  RuntimeAgentStateRepository? _runtimeStateRepository() {
    final configured = widget.runtimeAgentStateRepository;
    if (configured != null) return configured;
    if (_selfManagedRuntimeConnection != null) {
      return SecretaryRuntimeAgentStateRepository();
    }
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    if (cloudAuthScope == null) return null;
    return SecretaryRuntimeAgentStateRepository.hostedManagedPro(
      apiBaseUrl: cloudAuthScope.gatewayConfig.baseUrl,
      hostedSessionTokenGetter: cloudAuthScope.controller.getIdToken,
    );
  }

  ChatRuntimeConversationSender? _runtimeConversationSender() {
    final configured = widget.runtimeConversationSender;
    if (configured != null) return configured;
    if (_selfManagedRuntimeConnection != null) {
      return SecretaryRuntimeConversationSender();
    }
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    if (cloudAuthScope == null) return null;
    return SecretaryRuntimeConversationSender.hostedManagedPro(
      apiBaseUrl: cloudAuthScope.gatewayConfig.baseUrl,
      hostedSessionTokenGetter: cloudAuthScope.controller.getIdToken,
    );
  }

  ChatRuntimeEntityFocusSender? _runtimeEntityFocusSender() {
    final Object? configured = widget.runtimeConversationSender;
    if (configured is ChatRuntimeEntityFocusSender) return configured;
    final Object? sender = _runtimeConversationSender();
    return sender is ChatRuntimeEntityFocusSender ? sender : null;
  }

  ChatRuntimeAttachmentContentFetcher? _runtimeAttachmentContentFetcher() {
    final Object? configured = widget.runtimeConversationSender;
    if (configured is ChatRuntimeAttachmentContentFetcher) return configured;
    final Object? sender = _runtimeConversationSender();
    return sender is ChatRuntimeAttachmentContentFetcher ? sender : null;
  }
}
