part of 'cloud_sync_switch_prompt_gate_test.dart';

void registerCloudSyncSwitchPromptGateRecoveryTests() {
  testWidgets(
      'Switching to Cloud rolls back config when initial sync hits storage quota',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _StorageQuotaExceededPushBackend();
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
    expect(find.textContaining('Cloud storage is full'), findsOneWidget);
  });

  testWidgets(
      'Switching to Cloud rolls back config when recovery is blocked by local unpushed changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _LocalUnpushedChangesRecoveryBlockedPushBackend();
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
    final blockedScopeId = store.syncStateScopeIdForFields(
      backendType: SyncBackendType.managedVault,
      baseUrl: 'https://vault.example.com',
      remoteRoot: 'uid_1',
      syncKey: Uint8List.fromList(List<int>.filled(32, 9)),
    );
    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: blockedScopeId,
      ),
      isTrue,
    );
    expect(
      find.textContaining(
        'Local changes still need to upload before cloud recovery can continue.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'Switching to Cloud rolls back config when recovery is blocked by local media backfill',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _LocalMediaBackfillRecoveryBlockedPushBackend();
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
    final blockedScopeId = store.syncStateScopeIdForFields(
      backendType: SyncBackendType.managedVault,
      baseUrl: 'https://vault.example.com',
      remoteRoot: 'uid_1',
      syncKey: Uint8List.fromList(List<int>.filled(32, 9)),
    );
    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: blockedScopeId,
      ),
      isTrue,
    );
    expect(
      find.textContaining(
        'Local media still needs cloud backfill before recovery can continue.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'Switching to Cloud transient push failures do not clear an existing repair block',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    final managedVaultSyncKey = Uint8List.fromList(List<int>.filled(32, 9));
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    final blockedScopeId = store.syncStateScopeIdForFields(
      backendType: SyncBackendType.managedVault,
      baseUrl: 'https://vault.example.com',
      remoteRoot: 'uid_1',
      syncKey: managedVaultSyncKey,
    );
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: blockedScopeId,
    );

    final backend = _TransientManagedVaultPushBackend();
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
    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: blockedScopeId,
      ),
      isTrue,
    );
  });

  testWidgets(
      'Switching to Cloud retries push after pull recovers generation mismatch',
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

    final backend = _GenerationMismatchRecoveryPushBackend();
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

    expect(
      backend.calls,
      <String>[
        'syncManagedVaultPush',
        'syncManagedVaultPull',
        'syncManagedVaultPush',
        'syncManagedVaultPull',
      ],
    );
    expect(find.textContaining('managed-vault push failed'), findsNothing);
    engine.stop();
  });

  testWidgets(
      'Switching to Cloud rolls back config when retry push fails after recovery pull',
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

    final backend = _GenerationMismatchThenGraceReadOnlyPushBackend();
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

    expect(
      backend.calls,
      <String>[
        'syncManagedVaultPush',
        'syncManagedVaultPull',
        'syncManagedVaultPush',
      ],
    );
    expect(await store.readBackendType(), SyncBackendType.webdav);
    expect(await store.readRemoteRoot(), 'SecondLoop');
    expect((await store.readSyncKey())?.toList(), List<int>.filled(32, 7));
    expect(engine.writeGate.value.kind, SyncWriteGateKind.open);
    expect(find.textContaining('Cloud sync is read-only'), findsOneWidget);
    engine.stop();
  });

  testWidgets(
      'Switching to Cloud clears stale managed-vault write gate on success',
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

    final backend = _SuccessfulPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final engine = SyncEngine(
      syncRunner: _CountingSyncRunner(),
      loadConfig: () async => null,
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );
    engine.writeGate.value =
        const SyncWriteGateState.graceReadOnly(9999999999999);

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

    expect(backend.calls, contains('syncManagedVaultPush'));
    expect(engine.writeGate.value.kind, SyncWriteGateKind.open);
    engine.stop();
  });
}
