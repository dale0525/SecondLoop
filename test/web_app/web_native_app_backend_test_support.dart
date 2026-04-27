part of 'web_native_app_backend_test.dart';

final class _ProgressWrappingBackend extends WebNativeAppBackend {
  _ProgressWrappingBackend({
    required super.appDirProvider,
    required super.secureStorage,
    required super.rustLibInit,
    this.pullResult = 0,
    this.pushResult = 0,
  });

  final int pullResult;
  final int pushResult;

  int pullCalls = 0;
  int pushCalls = 0;

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    pullCalls += 1;
    return pullResult;
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    pushCalls += 1;
    return pushResult;
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    pushCalls += 1;
    return pushResult;
  }
}

final class _TaskPriorityBridgeService extends WebAppService {
  String? fetchedIdToken;
  String? fetchedScope;
  String? upsertedIdToken;
  Map<String, Object?>? upsertedPayload;

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription({
    required String idToken,
  }) async {
    return const WebSubscriptionSnapshot(
      state: WebSubscriptionState.entitled,
      canManageSubscription: true,
    );
  }

  @override
  Future<Map<String, Object?>> fetchTaskPriorityAssessments({
    required String idToken,
    required String scope,
  }) async {
    fetchedIdToken = idToken;
    fetchedScope = scope;
    return <String, Object?>{
      'scope': scope,
      'entries': <Object?>[
        <String, Object?>{
          'todo_id': 'focus',
          'semantic_adjustment': 8,
          'reason': 'shared',
          'confidence': 'high',
          'request_signature': 'sig-1',
          'computed_at_ms': 1710000000000,
        },
      ],
    };
  }

  @override
  Future<void> upsertTaskPriorityAssessments({
    required String idToken,
    required Map<String, Object?> payload,
  }) async {
    upsertedIdToken = idToken;
    upsertedPayload = payload;
  }
}

final class _CloudChatBridgeService extends WebAppService {
  _CloudChatBridgeService({this.reply = 'web reply'});

  final String reply;
  String? idToken;
  List<Map<String, String>>? messages;

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription({
    required String idToken,
  }) async {
    return const WebSubscriptionSnapshot(
      state: WebSubscriptionState.entitled,
      canManageSubscription: true,
    );
  }

  @override
  Future<String> sendChat({
    required String idToken,
    required List<Map<String, String>> messages,
  }) async {
    this.idToken = idToken;
    this.messages = List<Map<String, String>>.from(messages);
    return reply;
  }
}

final class _CloudChatBridgeBackend extends WebNativeAppBackend {
  _CloudChatBridgeBackend({
    required super.appDirProvider,
    required super.secureStorage,
    required super.rustLibInit,
    required super.webAppService,
  });

  final List<Map<String, String>> storedMessages = <Map<String, String>>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
    bool isMemory = false,
  }) async {
    storedMessages.add(<String, String>{'role': role, 'content': content});
    return Message(
      id: 'message-${storedMessages.length - 1}',
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: PlatformInt64Util.from(0),
      isMemory: isMemory,
    );
  }

  @override
  Future<List<Message>> listMessages(
    Uint8List key,
    String conversationId,
  ) async {
    return storedMessages.asMap().entries.map((entry) {
      final message = entry.value;
      return Message(
        id: 'message-${entry.key}',
        conversationId: conversationId,
        role: message['role']!,
        content: message['content']!,
        createdAtMs: PlatformInt64Util.from(0),
        isMemory: false,
      );
    }).toList(growable: false);
  }
}

final class _ManagedVaultPullBridgeService extends WebAppService {
  _ManagedVaultPullBridgeService({
    required List<WebManagedVaultPullPage> pages,
    List<Object> failures = const <Object>[],
    List<Object>? responses,
  })  : _pages = List<WebManagedVaultPullPage>.from(pages),
        _failures = List<Object>.from(failures),
        _responses = responses == null ? null : List<Object>.from(responses);

  final List<WebManagedVaultPullPage> _pages;
  final List<Object> _failures;
  final List<Object>? _responses;
  final List<int> afterGlobalSeqs = <int>[];
  final List<String> idTokens = <String>[];

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription({
    required String idToken,
  }) async {
    return const WebSubscriptionSnapshot(
      state: WebSubscriptionState.entitled,
      canManageSubscription: true,
    );
  }

  @override
  Future<WebManagedVaultPullPage> fetchManagedVaultPullPage({
    required String idToken,
    required String vaultId,
    required int afterGlobalSeq,
    int limit = 500,
  }) async {
    idTokens.add(idToken);
    afterGlobalSeqs.add(afterGlobalSeq);
    final responses = _responses;
    if (responses != null) {
      if (responses.isEmpty) {
        throw StateError('unexpected_pull_page_request');
      }
      final next = responses.removeAt(0);
      if (next is WebManagedVaultPullPage) return next;
      throw next;
    }
    if (_failures.isNotEmpty) {
      throw _failures.removeAt(0);
    }
    if (_pages.isEmpty) {
      throw StateError('unexpected_pull_page_request');
    }
    return _pages.removeAt(0);
  }
}

final class _ManagedVaultPullBridgeBackend extends WebNativeAppBackend {
  _ManagedVaultPullBridgeBackend({
    required super.appDirProvider,
    required super.secureStorage,
    required super.rustLibInit,
    required super.webAppService,
    List<String> recoveryReasons = const <String>[],
    Completer<void>? finalizeCompleter,
  })  : _recoveryReasons = List<String>.from(recoveryReasons),
        _finalizeCompleter = finalizeCompleter;

  final List<WebManagedVaultPullPage> appliedPages =
      <WebManagedVaultPullPage>[];
  final List<int> finalizedAppliedOps = <int>[];
  final List<String> _recoveryReasons;
  final Completer<void>? _finalizeCompleter;
  int _lastAppliedGlobalSeq = 0;
  String? _generationId;
  int _recoveredLastAppliedGlobalSeq = 0;
  String? _recoveredGenerationId;
  int recoveryCalls = 0;

  void seedPullState({
    String? generationId,
    required int lastAppliedGlobalSeq,
  }) {
    _generationId = generationId;
    _lastAppliedGlobalSeq = lastAppliedGlobalSeq;
  }

  void seedRecoveredPullState({
    String? generationId,
    required int lastAppliedGlobalSeq,
  }) {
    _recoveredGenerationId = generationId;
    _recoveredLastAppliedGlobalSeq = lastAppliedGlobalSeq;
  }

  @override
  Future<ManagedVaultV2PullState> readManagedVaultV2PullState({
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) async {
    return ManagedVaultV2PullState(
      generationId: _generationId,
      lastAppliedGlobalSeq: _lastAppliedGlobalSeq,
    );
  }

  @override
  Future<ManagedVaultV2PullApplyResult> applyManagedVaultV2PullPage(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required WebManagedVaultPullPage page,
  }) async {
    if (_recoveryReasons.isNotEmpty) {
      final recoveryReason = _recoveryReasons.removeAt(0);
      _generationId = null;
      _lastAppliedGlobalSeq = 0;
      return ManagedVaultV2PullApplyResult(
        appliedCount: 0,
        generationId: _generationId,
        lastAppliedGlobalSeq: _lastAppliedGlobalSeq,
        remoteLatestGlobalSeq: page.remoteLatestGlobalSeq,
        hasMore: page.hasMore,
        retryRequired: true,
        recoveryReason: recoveryReason,
      );
    }
    appliedPages.add(page);
    _generationId = page.generationId;
    if (page.ops.isNotEmpty) {
      _lastAppliedGlobalSeq = page.ops.last.globalSeq;
    }
    return ManagedVaultV2PullApplyResult(
      appliedCount: page.ops.length,
      generationId: _generationId,
      lastAppliedGlobalSeq: _lastAppliedGlobalSeq,
      remoteLatestGlobalSeq: page.remoteLatestGlobalSeq,
      hasMore: page.hasMore,
    );
  }

  @override
  Future<ManagedVaultV2PullState> recoverManagedVaultV2PullState(
    Uint8List key, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) async {
    recoveryCalls += 1;
    _generationId = _recoveredGenerationId;
    _lastAppliedGlobalSeq = _recoveredLastAppliedGlobalSeq;
    return ManagedVaultV2PullState(
      generationId: _generationId,
      lastAppliedGlobalSeq: _lastAppliedGlobalSeq,
    );
  }

  @override
  Future<void> finalizeManagedVaultV2Pull(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required int appliedOps,
  }) async {
    finalizedAppliedOps.add(appliedOps);
    await _finalizeCompleter?.future;
  }
}
