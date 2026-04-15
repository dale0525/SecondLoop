import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/web_app/web_local_runtime_recovery_base.dart';
import 'package:secondloop/web_app/web_initial_sync_gate.dart';
import 'package:secondloop/web_app/web_native_app_backend.dart';
import 'package:secondloop/web_app/web_persistent_app_dir.dart';

import '../test_backend.dart';
import '../test_i18n.dart';

class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  _FakeCloudAuthController({
    this.initialUid,
    this.initialEmail,
    this.initialEmailVerified,
  })  : _uid = initialUid,
        _email = initialEmail,
        _emailVerified = initialEmailVerified;

  final String? initialUid;
  final String? initialEmail;
  final bool? initialEmailVerified;
  String? _uid;
  String? _email;
  bool? _emailVerified;

  @override
  String? get uid => _uid;

  @override
  String? get email => _email;

  @override
  bool? get emailVerified => _emailVerified;

  @override
  Future<String?> getIdToken() async => _uid == null ? null : 'token';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _uid = 'uid-1';
    _email = email;
    _emailVerified = false;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _email = null;
    _emailVerified = null;
    notifyListeners();
  }

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _uid = 'uid-2';
    _email = email;
    _emailVerified = false;
    notifyListeners();
  }
}

class _FakeWebNativeBackend extends TestAppBackend {
  int syncManagedVaultPullCalls = 0;
  int deriveSyncKeyCalls = 0;
  String? lastDerivedPassphrase;
  Uint8List? lastSyncKey;

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    deriveSyncKeyCalls += 1;
    lastDerivedPassphrase = passphrase;
    return Uint8List.fromList(List<int>.filled(32, 3));
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    syncManagedVaultPullCalls += 1;
    lastSyncKey = Uint8List.fromList(syncKey);
    return 1;
  }
}

final class _FakeRuntimeResolver implements WebPersistentAppDirResolver {
  int bumpGenerationCalls = 0;

  @override
  Future<int> bumpGeneration({required String uid}) async {
    bumpGenerationCalls += 1;
    return bumpGenerationCalls;
  }

  @override
  Future<int> readGeneration({required String uid}) async => 0;

  @override
  Future<String> resolve({required String uid}) async =>
      '/opfs/secondloop/vaults/$uid/v0';
}

final class _FakeRuntimeRecovery implements WebLocalRuntimeRecovery {
  bool attempted = false;
  int reloadCalls = 0;

  @override
  void clearResetAttempted({required String uid}) {
    attempted = false;
  }

  @override
  bool hasAttemptedReset({required String uid}) => attempted;

  @override
  void markResetAttempted({required String uid}) {
    attempted = true;
  }

  @override
  Future<void> reloadPage() async {
    reloadCalls += 1;
  }
}

final class _EmptyWebNativeBackend extends WebNativeAppBackend {
  _EmptyWebNativeBackend()
      : super(
          appDirProvider: () async => '/opfs/secondloop/vaults/uid-1/v0',
          storageScope: 'web-native:uid-1',
          rustLibInit: () async {},
        );

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async =>
      const <Conversation>[];
}

final class _PendingWebNativeBackend extends WebNativeAppBackend {
  _PendingWebNativeBackend()
      : super(
          appDirProvider: () async => '/opfs/secondloop/vaults/uid-1/v0',
          storageScope: 'web-native:uid-1',
          rustLibInit: () async {},
        );

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async =>
      <Conversation>[
        const Conversation(
          id: 'conversation-1',
          title: 'Synced',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ];
}

final class _FailingWebNativeBackend extends WebNativeAppBackend {
  _FailingWebNativeBackend()
      : super(
          appDirProvider: () async => '/opfs/secondloop/vaults/uid-1/v0',
          storageScope: 'web-native:uid-1',
          rustLibInit: () async {},
        );

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async {
    throw StateError('opfs_unavailable');
  }
}

void main() {
  testWidgets(
      'first entitled launch triggers managed-vault pull before chat loads',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _FakeWebNativeBackend();
    final store = SyncConfigStore();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
              lock: () {},
              child: WebInitialSyncGate(
                authController: _FakeCloudAuthController(
                  initialUid: 'uid-1',
                  initialEmail: 'user@example.com',
                  initialEmailVerified: true,
                ),
                managedVaultBaseUrl: 'https://service-vault.secondloop.app',
                syncConfigStore: store,
                child: const Placeholder(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(backend.syncManagedVaultPullCalls, 1);
    expect(backend.deriveSyncKeyCalls, 1);
    expect(
      backend.lastDerivedPassphrase,
      'managed-vault-sync-v1::uid-1',
    );
    expect(backend.lastSyncKey, Uint8List.fromList(List<int>.filled(32, 3)));
    expect(
        await store.readSyncKey(), Uint8List.fromList(List<int>.filled(32, 3)));
  });

  testWidgets(
      'web initial sync gate does not reset local runtime when an entitled vault is simply empty',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final resolver = _FakeRuntimeResolver();
    final recovery = _FakeRuntimeRecovery();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _EmptyWebNativeBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
              lock: () {},
              child: WebInitialSyncGate(
                authController: _FakeCloudAuthController(
                  initialUid: 'uid-1',
                  initialEmail: 'user@example.com',
                  initialEmailVerified: true,
                ),
                managedVaultBaseUrl: 'https://service-vault.secondloop.app',
                syncRunner: (_, __, ___) async {},
                appDirResolver: resolver,
                localRuntimeRecovery: recovery,
                child: const Placeholder(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(resolver.bumpGenerationCalls, 0);
    expect(recovery.reloadCalls, 0);
    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets(
      'web initial sync gate rotates local runtime once when local runtime reads fail after sync',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final resolver = _FakeRuntimeResolver();
    final recovery = _FakeRuntimeRecovery();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _FailingWebNativeBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
              lock: () {},
              child: WebInitialSyncGate(
                authController: _FakeCloudAuthController(
                  initialUid: 'uid-1',
                  initialEmail: 'user@example.com',
                  initialEmailVerified: true,
                ),
                managedVaultBaseUrl: 'https://service-vault.secondloop.app',
                syncRunner: (_, __, ___) async {},
                appDirResolver: resolver,
                localRuntimeRecovery: recovery,
                child: const Placeholder(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(resolver.bumpGenerationCalls, 1);
    expect(recovery.reloadCalls, 1);
    expect(find.byType(Placeholder), findsNothing);
  });

  testWidgets('web initial sync gate stops blocking the shell after timeout',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final syncCompleter = Completer<void>();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _FakeWebNativeBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
              lock: () {},
              child: WebInitialSyncGate(
                authController: _FakeCloudAuthController(
                  initialUid: 'uid-1',
                  initialEmail: 'user@example.com',
                  initialEmailVerified: true,
                ),
                managedVaultBaseUrl: 'https://service-vault.secondloop.app',
                syncRunner: (_, __, ___) => syncCompleter.future,
                blockingTimeout: const Duration(milliseconds: 100),
                child: const Placeholder(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Placeholder), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(Placeholder), findsOneWidget);

    syncCompleter.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets(
      'web initial sync gate keeps blocking web-native shell while sync is pending',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final syncCompleter = Completer<void>();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _PendingWebNativeBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
              lock: () {},
              child: WebInitialSyncGate(
                authController: _FakeCloudAuthController(
                  initialUid: 'uid-1',
                  initialEmail: 'user@example.com',
                  initialEmailVerified: true,
                ),
                managedVaultBaseUrl: 'https://service-vault.secondloop.app',
                syncRunner: (_, __, ___) => syncCompleter.future,
                blockingTimeout: const Duration(milliseconds: 100),
                child: const Placeholder(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Placeholder), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(Placeholder), findsNothing);

    syncCompleter.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(Placeholder), findsOneWidget);
  });
}
