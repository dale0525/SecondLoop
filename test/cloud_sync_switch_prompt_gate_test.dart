import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/cloud_sync_switch_prompt_gate.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_diagnostics.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

part 'cloud_sync_switch_prompt_gate_recovery_part.dart';
part 'cloud_sync_switch_prompt_gate_test_support_part.dart';

void main() {
  testWidgets(
      'Entitled subscription prompts switching to SecondLoop Cloud sync',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.unknown);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            child: SubscriptionScope(
              controller: subscription,
              child: CloudSyncSwitchPromptGate(
                configStore: store,
                child: const Scaffold(body: Text('home')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);

    subscription.setStatus(SubscriptionStatus.entitled);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Already-entitled subscription prompts immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            child: SubscriptionScope(
              controller: subscription,
              child: CloudSyncSwitchPromptGate(
                configStore: store,
                child: const Scaffold(body: Text('home')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Prompt works when gate is above Navigator (MaterialApp.builder)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final navigatorKey = GlobalKey<NavigatorState>();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.unknown);

    await tester.pumpWidget(
      wrapWithI18n(
        CloudAuthScope(
          controller: cloudAuth,
          child: SubscriptionScope(
            controller: subscription,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: const Scaffold(body: Text('home')),
              builder: (context, child) {
                return CloudSyncSwitchPromptGate(
                  navigatorKey: navigatorKey,
                  configStore: store,
                  child: child ?? const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);

    subscription.setStatus(SubscriptionStatus.entitled);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Switching to Cloud derives managed vault sync key from uid',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _Backend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.unknown);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: cloudAuth,
                child: SubscriptionScope(
                  controller: subscription,
                  child: CloudSyncSwitchPromptGate(
                    configStore: store,
                    child: const Scaffold(body: Text('home')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    subscription.setStatus(SubscriptionStatus.entitled);
    await tester.pumpAndSettle();

    await _tapSwitchAndChooseMerge(tester);
    await tester.pumpAndSettle();

    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(await store.readRemoteRoot(), 'uid_1');
    final syncKey = await store.readSyncKey();
    expect(syncKey, isNotNull);
    expect(syncKey, Uint8List.fromList(List<int>.filled(32, 9)));
    expect(find.text('Enter your recovery passphrase and tap Save first.'),
        findsNothing);
  });

  testWidgets(
      'Switching to Cloud does not persist managed-vault config when bootstrap prerequisites are missing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final previousSyncKey = Uint8List.fromList(List<int>.filled(32, 7));
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(previousSyncKey);

    final backend = _Backend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.unknown);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              child: SubscriptionScope(
                controller: subscription,
                child: CloudSyncSwitchPromptGate(
                  configStore: store,
                  child: const Scaffold(body: Text('home')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    subscription.setStatus(SubscriptionStatus.entitled);
    await tester.pumpAndSettle();

    await _tapSwitchAndChooseMerge(tester);
    await tester.pumpAndSettle();

    expect(await store.readBackendType(), SyncBackendType.webdav);
    expect(await store.readRemoteRoot(), 'SecondLoop');
    expect(await store.readSyncKey(), previousSyncKey);
  });

  testWidgets(
      'Cloud sync switch prompt continues to a single AI feature guide prompt and can open AI settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      // Can be set by previous Ask AI / settings interactions.
      'embeddings_data_consent_v1': false,
    });
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final navigatorKey = GlobalKey<NavigatorState>();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('home')),
          builder: (context, child) {
            return CloudAuthScope(
              controller: cloudAuth,
              child: SubscriptionScope(
                controller: subscription,
                child: CloudSyncSwitchPromptGate(
                  navigatorKey: navigatorKey,
                  configStore: store,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('More AI features are now available'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai_settings_home_smart_organization')),
      findsOneWidget,
    );
  });

  testWidgets(
      'Switching to Cloud runs push before pull and shows progress first',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      // Consent should still be prompted after the sync completes.
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _SuccessfulPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: cloudAuth,
                child: SubscriptionScope(
                  controller: subscription,
                  child: CloudSyncSwitchPromptGate(
                    configStore: store,
                    child: const Scaffold(body: Text('home')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch prompt shows first.
    expect(find.text('Switch'), findsOneWidget);
    await _tapSwitchAndChooseMerge(tester);

    // Sync progress dialog appears before the AI guide prompt.
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('cloud_sync_switch_progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cloud_sync_switch_progress_percent')),
      findsOneWidget,
    );
    expect(
      find.text('More AI features are now available'),
      findsNothing,
    );

    // After sync finishes, the AI guide prompt appears.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>['syncManagedVaultPush', 'syncManagedVaultPull'],
    );
    expect(find.text('More AI features are now available'), findsOneWidget);
  });

  testWidgets(
      'Switching to Cloud falls back to engine push/pull when progress sync fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _FailingPullBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final syncRunner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: syncRunner,
      loadConfig: () async => SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
        vaultId: 'uid_1',
        baseUrl: 'https://vault.example.com',
      ),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );
    engine.start();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: CloudAuthScope(
                  controller: cloudAuth,
                  child: SubscriptionScope(
                    controller: subscription,
                    child: CloudSyncSwitchPromptGate(
                      configStore: store,
                      child: const Scaffold(body: Text('home')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await _tapSwitchAndChooseMerge(tester);
    await tester.pumpAndSettle();

    expect(backend.calls, contains('syncManagedVaultPull'));
    expect(syncRunner.pullCalls, 1);
    expect(syncRunner.pushCalls, 1);

    engine.stop();
  });

  testWidgets(
      'Switching to Cloud rolls back config when initial sync fails unrecoverably',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeCloudMediaBackupEnabled(false);

    final backend = _InvalidBatchPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: cloudAuth,
                child: SubscriptionScope(
                  controller: subscription,
                  child: CloudSyncSwitchPromptGate(
                    configStore: store,
                    child: const Scaffold(body: Text('home')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await _tapSwitchAndChooseMerge(tester);
    await tester.pumpAndSettle();

    expect(backend.calls, <String>['syncManagedVaultPush']);
    expect(await store.readBackendType(), SyncBackendType.webdav);
    expect(await store.readRemoteRoot(), 'SecondLoop');
    expect((await store.readSyncKey())?.toList(), List<int>.filled(32, 7));
    expect(
      find.textContaining(
        'Local sync data needs repair before cloud sync can continue.',
      ),
      findsOneWidget,
    );
    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: store.syncStateScopeIdForFields(
          backendType: SyncBackendType.managedVault,
          baseUrl: 'https://vault.example.com',
          remoteRoot: 'uid_1',
          syncKey: Uint8List.fromList(List<int>.filled(32, 9)),
        ),
      ),
      isTrue,
    );
  });

  testWidgets(
      'Switching to Cloud rolls back config when push is read-only blocked',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _GraceReadOnlyPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final engine = SyncEngine(
      syncRunner: _CountingSyncRunner(),
      loadConfig: () async => SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
        vaultId: 'uid_1',
        baseUrl: 'https://vault.example.com',
      ),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );
    engine.start();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: CloudAuthScope(
                  controller: cloudAuth,
                  child: SubscriptionScope(
                    controller: subscription,
                    child: CloudSyncSwitchPromptGate(
                      configStore: store,
                      child: const Scaffold(body: Text('home')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await _tapSwitchAndChooseMerge(tester);
    await tester.pumpAndSettle();

    expect(backend.calls, <String>['syncManagedVaultPush']);
    expect(await store.readBackendType(), SyncBackendType.webdav);
    expect(await store.readRemoteRoot(), 'SecondLoop');
    expect((await store.readSyncKey())?.toList(), List<int>.filled(32, 7));
    expect(engine.writeGate.value.kind, SyncWriteGateKind.open);
    expect(find.textContaining('Cloud sync is read-only'), findsOneWidget);
    engine.stop();
  });

  testWidgets('Cloud session switch preserves existing random sync key',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final previousSyncKey = Uint8List.fromList(List<int>.filled(32, 7));
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(previousSyncKey);
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeCloudMediaBackupEnabled(false);

    final backend = _SuccessfulPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppPlatformCapabilityScope(
            capabilities: AppPlatformCapabilities.webCloud(),
            child: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: CloudAuthScope(
                  controller: cloudAuth,
                  child: SubscriptionScope(
                    controller: subscription,
                    child: CloudSyncSwitchPromptGate(
                      configStore: store,
                      child: const Scaffold(body: Text('home')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await _tapSwitchAndChooseMerge(tester);
    await tester.pumpAndSettle();

    expect(backend.calls,
        <String>['syncManagedVaultPush', 'syncManagedVaultPull']);
    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(await store.readRemoteRoot(), 'uid_1');
    expect((await store.readSyncKey())?.toList(), previousSyncKey.toList());
  });

  testWidgets('Switching to Cloud clears background repair block after success',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeCloudMediaBackupEnabled(false);
    final scopeId = store.syncStateScopeIdForFields(
      backendType: SyncBackendType.managedVault,
      baseUrl: 'https://vault.example.com',
      remoteRoot: 'uid_1',
      syncKey: Uint8List.fromList(List<int>.filled(32, 9)),
    );
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );
    await store.writeBackgroundSyncBackoffState(
      const SyncBackgroundBackoffState(
        backendType: SyncBackendType.managedVault,
        retryCount: 2,
        nextAllowedAtMs: 999999,
        updatedAtMs: 999000,
        lastStatusCode: 503,
        lastErrorCode: 'server_error',
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );

    final backend = _SuccessfulManagedVaultBootstrapBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: cloudAuth,
                child: SubscriptionScope(
                  controller: subscription,
                  child: CloudSyncSwitchPromptGate(
                    configStore: store,
                    child: const Scaffold(body: Text('home')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapSwitchAndChooseMerge(tester);
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>['syncManagedVaultPush', 'syncManagedVaultPull'],
    );
    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeId,
      ),
      isFalse,
    );
    expect(
      await store.readBackgroundSyncBackoffState(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeId,
      ),
      isNull,
    );
  });

  registerCloudSyncSwitchPromptGateRecoveryTests();
}
