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
