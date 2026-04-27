import 'dart:async';
import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/web_app/web_app_service.dart';
import 'package:secondloop/web_app/web_formal_settings_adapters.dart';
import 'package:secondloop/web_app/web_native_app_backend.dart';

part 'web_native_app_backend_test_support.dart';

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

  test('WebNativeAppBackend wraps managed-vault push ops-only progress on web',
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

  test('WebNativeAppBackend wraps managed-vault full push progress on web',
      () async {
    final backend = _ProgressWrappingBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      pushResult: 4,
    );

    final events = await backend
        .syncManagedVaultPushProgress(
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
        '{"type":"result","count":4}',
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

  test('WebNativeAppBackend bridges cloud chat through WebAppService',
      () async {
    final service = _CloudChatBridgeService();
    final backend = _CloudChatBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
    );

    final events = await backend
        .askAiStreamCloudGateway(
          Uint8List(32),
          'conversation-1',
          question: 'Summarize this',
          gatewayBaseUrl: kWebFormalSettingsBaseUrl,
          idToken: 'token-1',
          modelName: 'cloud',
        )
        .toList();

    expect(events, <String>['web reply']);
    expect(service.idToken, 'token-1');
    expect(service.messages, <Map<String, String>>[
      <String, String>{'role': 'user', 'content': 'Summarize this'},
    ]);
  });

  test(
      'WebNativeAppBackend bridges task-priority rerank chat through WebAppService',
      () async {
    final service = _CloudChatBridgeService(reply: 'reranked');
    final backend = WebNativeAppBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
    );

    final reply = await backend.taskPriorityRerankAiCloudGateway(
      Uint8List(32),
      prompt: 'rank todos',
      gatewayBaseUrl: kWebFormalSettingsBaseUrl,
      idToken: 'token-2',
      modelName: 'cloud',
    );

    expect(reply, 'reranked');
    expect(service.idToken, 'token-2');
    expect(service.messages, <Map<String, String>>[
      <String, String>{'role': 'user', 'content': 'rank todos'},
    ]);
  });

  test(
      'WebNativeAppBackend bridges managed-vault pull for real website proxy URL',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[
        const WebManagedVaultPullPage(
          generationId: 'generation-1',
          remoteLatestGlobalSeq: 1,
          hasMore: false,
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
      baseUrl: 'https://site.secondloop.app/api/app/vault-proxy',
      vaultId: 'vault-123',
      idToken: 'token-1',
    );

    expect(pulled, 1);
    expect(service.afterGlobalSeqs, <int>[0]);
    expect(backend.appliedPages, hasLength(1));
    expect(backend.finalizedAppliedOps, <int>[1]);
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
      baseUrl: kWebFormalSettingsBaseUrl,
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
      'WebNativeAppBackend only bridges managed-vault pull for web formal settings base URL',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[
        const WebManagedVaultPullPage(
          generationId: 'generation-1',
          remoteLatestGlobalSeq: 1,
          hasMore: false,
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
      ],
    );
    final backend = _ManagedVaultPullBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
    );

    await expectLater(
      () => backend.syncManagedVaultPull(
        Uint8List(32),
        Uint8List(32),
        baseUrl: 'https://service-vault.secondloop.app',
        vaultId: 'vault-123',
        idToken: 'token-1',
      ),
      throwsA(anything),
    );

    expect(service.afterGlobalSeqs, isEmpty);
    expect(backend.appliedPages, isEmpty);
    expect(backend.finalizedAppliedOps, isEmpty);
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
      baseUrl: kWebFormalSettingsBaseUrl,
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
      baseUrl: kWebFormalSettingsBaseUrl,
      vaultId: 'vault-123',
      idToken: 'token-1',
    );

    expect(pulled, 1);
    expect(service.afterGlobalSeqs, <int>[8, 0]);
    expect(backend.recoveryCalls, 0);
    expect(backend.finalizedAppliedOps, <int>[1]);
  });

  test('WebNativeAppBackend stops after empty-remote-state recovery repeats',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[
        const WebManagedVaultPullPage(
          generationId: '',
          remoteLatestGlobalSeq: 0,
          hasMore: false,
          ops: <WebManagedVaultPullOp>[],
        ),
        const WebManagedVaultPullPage(
          generationId: '',
          remoteLatestGlobalSeq: 0,
          hasMore: false,
          ops: <WebManagedVaultPullOp>[],
        ),
      ],
    );
    final backend = _ManagedVaultPullBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
      recoveryReasons: <String>['empty_remote_state', 'empty_remote_state'],
    );
    backend.seedPullState(
      generationId: 'generation-1',
      lastAppliedGlobalSeq: 8,
    );

    await expectLater(
      () => backend.syncManagedVaultPull(
        Uint8List(32),
        Uint8List(32),
        baseUrl: kWebFormalSettingsBaseUrl,
        vaultId: 'vault-123',
        idToken: 'token-1',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('empty_remote_state'),
        ),
      ),
    );
    expect(service.afterGlobalSeqs, <int>[8, 0]);
    expect(backend.finalizedAppliedOps, isEmpty);
  });

  test('WebNativeAppBackend throws on unexpected managed-vault retry reason',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[
        const WebManagedVaultPullPage(
          generationId: 'generation-2',
          remoteLatestGlobalSeq: 1,
          hasMore: false,
          ops: <WebManagedVaultPullOp>[],
        ),
      ],
    );
    final backend = _ManagedVaultPullBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
      recoveryReasons: <String>['unexpected_reason'],
    );
    backend.seedPullState(
      generationId: 'generation-1',
      lastAppliedGlobalSeq: 8,
    );

    await expectLater(
      () => backend.syncManagedVaultPull(
        Uint8List(32),
        Uint8List(32),
        baseUrl: kWebFormalSettingsBaseUrl,
        vaultId: 'vault-123',
        idToken: 'token-1',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(
              'managed_vault_pull_unexpected_retry_reason:unexpected_reason'),
        ),
      ),
    );
    expect(service.afterGlobalSeqs, <int>[8]);
    expect(backend.finalizedAppliedOps, isEmpty);
  });

  test(
      'WebNativeAppBackend resets applied-op count after reset-required recovery rebuilds local state',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[],
      responses: <Object>[
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
        const WebAppHttpException(
          statusCode: 409,
          code: 'reset_required',
          body:
              '{"error":"reset_required","reason":"global_log_gap","remote_generation_id":"generation-1","remote_latest_global_seq":2}',
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
    backend.seedPullState(
      generationId: 'generation-1',
      lastAppliedGlobalSeq: 0,
    );
    backend.seedRecoveredPullState(
      generationId: 'generation-1',
      lastAppliedGlobalSeq: 1,
    );

    final pulled = await backend.syncManagedVaultPull(
      Uint8List(32),
      Uint8List(32),
      baseUrl: kWebFormalSettingsBaseUrl,
      vaultId: 'vault-123',
      idToken: 'token-1',
    );

    expect(pulled, 1);
    expect(service.afterGlobalSeqs, <int>[0, 1, 1]);
    expect(backend.finalizedAppliedOps, <int>[1]);
  });

  test('WebNativeAppBackend reports incremental managed-vault pull progress',
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

    final events = await backend
        .syncManagedVaultPullProgress(
          Uint8List(32),
          Uint8List(32),
          baseUrl: kWebFormalSettingsBaseUrl,
          vaultId: 'vault-123',
          idToken: 'token-1',
        )
        .toList();

    expect(
      events,
      <String>[
        '{"type":"progress","done":1,"total":2}',
        '{"type":"progress","done":2,"total":2}',
        '{"type":"result","count":2}',
      ],
    );
  });

  test('WebNativeAppBackend awaits async managed-vault pull finalization',
      () async {
    final service = _ManagedVaultPullBridgeService(
      pages: <WebManagedVaultPullPage>[
        const WebManagedVaultPullPage(
          generationId: 'generation-1',
          remoteLatestGlobalSeq: 1,
          hasMore: false,
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
      ],
    );
    final finalizeCompleter = Completer<void>();
    final backend = _ManagedVaultPullBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
      finalizeCompleter: finalizeCompleter,
    );

    var completed = false;
    final future = backend
        .syncManagedVaultPull(
      Uint8List(32),
      Uint8List(32),
      baseUrl: kWebFormalSettingsBaseUrl,
      vaultId: 'vault-123',
      idToken: 'token-1',
    )
        .then((_) {
      completed = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(backend.finalizedAppliedOps, <int>[1]);
    expect(completed, isFalse);

    finalizeCompleter.complete();
    await future;

    expect(completed, isTrue);
  });
}
