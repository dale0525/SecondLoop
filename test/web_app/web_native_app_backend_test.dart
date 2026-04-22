import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/web_app/web_app_service.dart';
import 'package:secondloop/web_app/web_formal_settings_adapters.dart';
import 'package:secondloop/web_app/web_native_app_backend.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('WebNativeAppBackend forwards appDirProvider into NativeAppBackend',
      () async {
    final backend = WebNativeAppBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
    );

    await backend.init();

    expect(
      await backend.debugResolvedAppDir(),
      '/opfs/secondloop/vaults/uid-1',
    );
  });

  test('WebNativeAppBackend persists saved session keys', () async {
    final backend = WebNativeAppBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
    );
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));

    await backend.saveSessionKey(key);

    expect(await backend.loadSavedSessionKey(), key);
  });

  test('WebNativeAppBackend isolates saved session keys by storage scope',
      () async {
    final first = WebNativeAppBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      storageScope: 'web-native:uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
    );
    final second = WebNativeAppBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-2',
      storageScope: 'web-native:uid-2',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
    );
    final firstKey = Uint8List.fromList(List<int>.filled(32, 1));
    final secondKey = Uint8List.fromList(List<int>.filled(32, 2));

    await first.saveSessionKey(firstKey);
    await second.saveSessionKey(secondKey);

    expect(await first.loadSavedSessionKey(), firstKey);
    expect(await second.loadSavedSessionKey(), secondKey);
  });

  test('WebNativeAppBackend wraps managed-vault pull progress on web',
      () async {
    final backend = _ProgressWrappingBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      pullResult: 7,
    );

    final events = await backend
        .syncManagedVaultPullProgress(
          Uint8List(32),
          Uint8List(32),
          baseUrl: 'https://service-vault.secondloop.app',
          vaultId: 'uid-1',
          idToken: 'token',
        )
        .toList();

    expect(backend.pullCalls, 1);
    expect(
      events,
      <String>[
        '{"type":"progress","done":0,"total":0}',
        '{"type":"result","count":7}',
      ],
    );
  });

  test('WebNativeAppBackend wraps managed-vault push progress on web',
      () async {
    final backend = _ProgressWrappingBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      pushResult: 3,
    );

    final events = await backend
        .syncManagedVaultPushOpsOnlyProgress(
          Uint8List(32),
          Uint8List(32),
          baseUrl: 'https://service-vault.secondloop.app',
          vaultId: 'uid-1',
          idToken: 'token',
        )
        .toList();

    expect(backend.pushCalls, 1);
    expect(
      events,
      <String>[
        '{"type":"progress","done":0,"total":0}',
        '{"type":"result","count":3}',
      ],
    );
  });

  test(
      'WebNativeAppBackend bridges shared task-priority assessments for web formal settings',
      () async {
    final service = _TaskPriorityBridgeService();
    final backend = WebNativeAppBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
    );

    final fetched = await backend.fetchTaskPriorityAiAssessmentsCloudGateway(
      Uint8List(32),
      gatewayBaseUrl: kWebFormalSettingsBaseUrl,
      idToken: 'token-1',
      cacheScopeKey: 'scope-1',
    );
    await backend.upsertTaskPriorityAiAssessmentsCloudGateway(
      Uint8List(32),
      gatewayBaseUrl: kWebFormalSettingsBaseUrl,
      idToken: 'token-1',
      cacheScopeKey: 'scope-1',
      payloadJson: jsonEncode(<String, Object?>{
        'scope': 'scope-1',
        'entries': <Object?>[],
      }),
    );

    expect(service.fetchedIdToken, 'token-1');
    expect(service.fetchedScope, 'scope-1');
    expect(jsonDecode(fetched)['scope'], 'scope-1');
    expect(service.upsertedIdToken, 'token-1');
    expect(service.upsertedPayload?['scope'], 'scope-1');
  });

  test('WebNativeAppBackend pulls managed-vault pages through WebAppService',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[
        const WebManagedVaultPullPage(
          generationId: 'generation-1',
          remoteLatestGlobalSeq: 2,
          hasMore: true,
          ops: <WebManagedVaultPullOp>[
            WebManagedVaultPullOp(
              globalSeq: 1,
              deviceId: 'device-a',
              seq: 11,
              opId: 'op-1',
              clientOpId: 'op-1',
              ciphertextB64: 'AQID',
            ),
          ],
        ),
        const WebManagedVaultPullPage(
          generationId: 'generation-1',
          remoteLatestGlobalSeq: 2,
          hasMore: false,
          ops: <WebManagedVaultPullOp>[
            WebManagedVaultPullOp(
              globalSeq: 2,
              deviceId: 'device-a',
              seq: 12,
              opId: 'op-2',
              clientOpId: 'op-2',
              ciphertextB64: 'BAUG',
            ),
          ],
        ),
      ],
    );
    final backend = _ManagedVaultPullBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
    );

    final pulled = await backend.syncManagedVaultPull(
      Uint8List(32),
      Uint8List(32),
      baseUrl: 'https://service-vault.secondloop.app',
      vaultId: 'vault-123',
      idToken: 'token-1',
    );

    expect(pulled, 2);
    expect(service.afterGlobalSeqs, <int>[0, 1]);
    expect(service.idTokens, <String>['token-1', 'token-1']);
    expect(backend.appliedPages, hasLength(2));
    expect(backend.appliedPages.first.ops.single.opId, 'op-1');
    expect(backend.appliedPages.last.ops.single.opId, 'op-2');
    expect(backend.finalizedAppliedOps, <int>[2]);
  });

  test(
      'WebNativeAppBackend retries reset-required web pull after safe recovery',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[
        const WebManagedVaultPullPage(
          generationId: 'generation-2',
          remoteLatestGlobalSeq: 1,
          hasMore: false,
          ops: <WebManagedVaultPullOp>[
            WebManagedVaultPullOp(
              globalSeq: 1,
              deviceId: 'device-a',
              seq: 21,
              opId: 'op-1',
              clientOpId: 'op-1',
              ciphertextB64: 'AQID',
            ),
          ],
        ),
      ],
      failures: <Object>[
        const WebAppHttpException(
          statusCode: 409,
          code: 'reset_required',
          body:
              '{"error":"reset_required","reason":"global_log_gap","remote_generation_id":"generation-2","remote_latest_global_seq":1}',
        ),
      ],
    );
    final backend = _ManagedVaultPullBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
    );
    backend.seedPullState(
        generationId: 'generation-1', lastAppliedGlobalSeq: 8);

    final pulled = await backend.syncManagedVaultPull(
      Uint8List(32),
      Uint8List(32),
      baseUrl: 'https://service-vault.secondloop.app',
      vaultId: 'vault-123',
      idToken: 'token-1',
    );

    expect(pulled, 1);
    expect(service.afterGlobalSeqs, <int>[8, 0]);
    expect(backend.recoveryCalls, 1);
    expect(backend.finalizedAppliedOps, <int>[1]);
  });

  test(
      'WebNativeAppBackend retries generation-mismatch apply after safe recovery',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[
        const WebManagedVaultPullPage(
          generationId: 'generation-2',
          remoteLatestGlobalSeq: 1,
          hasMore: false,
          ops: <WebManagedVaultPullOp>[],
        ),
        const WebManagedVaultPullPage(
          generationId: 'generation-2',
          remoteLatestGlobalSeq: 1,
          hasMore: false,
          ops: <WebManagedVaultPullOp>[
            WebManagedVaultPullOp(
              globalSeq: 1,
              deviceId: 'device-a',
              seq: 22,
              opId: 'op-2',
              clientOpId: 'op-2',
              ciphertextB64: 'AQID',
            ),
          ],
        ),
      ],
    );
    final backend = _ManagedVaultPullBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
      recoveryReasons: <String>['generation_mismatch'],
    );
    backend.seedPullState(
        generationId: 'generation-1', lastAppliedGlobalSeq: 8);

    final pulled = await backend.syncManagedVaultPull(
      Uint8List(32),
      Uint8List(32),
      baseUrl: 'https://service-vault.secondloop.app',
      vaultId: 'vault-123',
      idToken: 'token-1',
    );

    expect(pulled, 1);
    expect(service.afterGlobalSeqs, <int>[8, 0]);
    expect(backend.recoveryCalls, 1);
    expect(backend.finalizedAppliedOps, <int>[1]);
  });
}

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

final class _ManagedVaultPullBridgeService extends WebAppService {
  _ManagedVaultPullBridgeService({
    required List<WebManagedVaultPullPage> pages,
    List<Object> failures = const <Object>[],
  })  : _pages = List<WebManagedVaultPullPage>.from(pages),
        _failures = List<Object>.from(failures);

  final List<WebManagedVaultPullPage> _pages;
  final List<Object> _failures;
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
  }) : _recoveryReasons = List<String>.from(recoveryReasons);

  final List<WebManagedVaultPullPage> appliedPages =
      <WebManagedVaultPullPage>[];
  final List<int> finalizedAppliedOps = <int>[];
  final List<String> _recoveryReasons;
  int _lastAppliedGlobalSeq = 0;
  String? _generationId;
  int recoveryCalls = 0;

  void seedPullState({
    String? generationId,
    required int lastAppliedGlobalSeq,
  }) {
    _generationId = generationId;
    _lastAppliedGlobalSeq = lastAppliedGlobalSeq;
  }

  @override
  ManagedVaultV2PullState readManagedVaultV2PullState({
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) {
    return ManagedVaultV2PullState(
      generationId: _generationId,
      lastAppliedGlobalSeq: _lastAppliedGlobalSeq,
    );
  }

  @override
  ManagedVaultV2PullApplyResult applyManagedVaultV2PullPage(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required WebManagedVaultPullPage page,
  }) {
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
  ManagedVaultV2PullState recoverManagedVaultV2PullState(
    Uint8List key, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) {
    recoveryCalls += 1;
    _generationId = null;
    _lastAppliedGlobalSeq = 0;
    return ManagedVaultV2PullState(
      generationId: _generationId,
      lastAppliedGlobalSeq: _lastAppliedGlobalSeq,
    );
  }

  @override
  void finalizeManagedVaultV2Pull(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required int appliedOps,
  }) {
    finalizedAppliedOps.add(appliedOps);
  }
}
