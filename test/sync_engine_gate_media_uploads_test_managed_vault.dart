part of 'sync_engine_gate_media_uploads_test.dart';

void registerSyncEngineGateMediaUploadManagedVaultTests() {
  testWidgets(
      'Managed-vault auto sync uses full push and waits for pull before media uploads',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);
    final scopeId = store.syncStateScopeIdForFields(
      backendType: SyncBackendType.managedVault,
      baseUrl: 'https://vault.example.com',
      remoteRoot: 'vault-1',
      syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );
    await store.writeBackgroundSyncBackoffState(
      const SyncBackgroundBackoffState(
        backendType: SyncBackendType.managedVault,
        retryCount: 4,
        nextAllowedAtMs: 999999,
        updatedAtMs: 999000,
        lastStatusCode: 503,
        lastErrorCode: 'server_error',
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRecordingBackend(
        dueBackups: [
          const CloudMediaBackup(
            attachmentSha256: 'a',
            desiredVariant: 'original',
            byteLen: 0,
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            updatedAtMs: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: const SyncEngineGate(child: SizedBox.shrink()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPushCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushCalls, 1);
      expect(backend.managedVaultPushOpsOnlyCalls, 0);
      expect(backend.managedVaultUploadAttachmentCalls, 0);

      backend.completePull(applied: 0);

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPullCalls, 1);
      expect(backend.managedVaultUploadAttachmentCalls, 1);
      expect(backend.markUploadedCalls, 1);
      expect(
        await store.readBackgroundSyncBackoffState(
          backendType: SyncBackendType.managedVault,
          scopeId: scopeId,
        ),
        isNull,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault pull-only recovery uploads media for the active scoped queue after recovery pull',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultPullOnlyRecoveryBackend(
        dueBackups: [
          const CloudMediaBackup(
            attachmentSha256: 'a',
            desiredVariant: 'original',
            byteLen: 0,
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            updatedAtMs: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: const SyncEngineGate(child: SizedBox.shrink()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPullCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushCalls, 1);
      expect(backend.managedVaultPullCalls, 1);
      expect(backend.managedVaultUploadAttachmentCalls, 1);
      expect(backend.markUploadedCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault invalid batches persist the background repair block',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultInvalidBatchBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPushCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushCalls, 1);
      expect(engine, isNotNull);
      expect(
          engine!.writeGate.value.kind, SyncWriteGateKind.localRepairRequired);
      expect(
        await store.readBackgroundSyncRepairRequired(
          backendType: SyncBackendType.managedVault,
          scopeId: store.syncStateScopeIdForFields(
            backendType: SyncBackendType.managedVault,
            baseUrl: 'https://vault.example.com',
            remoteRoot: 'vault-1',
            syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
          ),
        ),
        isTrue,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault persisted repair block hydrates before foreground auto-push',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(false);
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: store.syncStateScopeId(
        SyncConfig.managedVault(
          syncKey: syncKey,
          vaultId: 'vault-1',
          baseUrl: 'https://vault.example.com',
        ),
      ),
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRecordingBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(engine, isNotNull);
      expect(
        engine!.writeGate.value.kind,
        SyncWriteGateKind.localRepairRequired,
      );
      expect(backend.managedVaultPushCalls, 0);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault transient pull failures do not clear an existing repair block',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    final config = SyncConfig.managedVault(
      syncKey: syncKey,
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
    );
    final scopeId = store.syncStateScopeId(config);
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(false);
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultTransientPullFailureBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPullCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(engine, isNotNull);
      expect(
          engine!.writeGate.value.kind, SyncWriteGateKind.localRepairRequired);
      expect(backend.managedVaultPushCalls, 0);
      expect(backend.managedVaultPullCalls, greaterThanOrEqualTo(1));
      expect(
        await store.readBackgroundSyncRepairRequired(
          backendType: SyncBackendType.managedVault,
          scopeId: scopeId,
        ),
        isTrue,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault transient push failures do not clear an existing repair block',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    final config = SyncConfig.managedVault(
      syncKey: syncKey,
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
    );
    final scopeId = store.syncStateScopeId(config);
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(false);
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultTransientPushFailureBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(engine, isNotNull);
      expect(
          engine!.writeGate.value.kind, SyncWriteGateKind.localRepairRequired);

      engine!.writeGate.value = const SyncWriteGateState.open();
      engine!.triggerPushNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPushCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushCalls, greaterThanOrEqualTo(1));
      expect(
        await store.readBackgroundSyncRepairRequired(
          backendType: SyncBackendType.managedVault,
          scopeId: scopeId,
        ),
        isTrue,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault successful pushes preserve an active media-backfill repair block',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    final config = SyncConfig.managedVault(
      syncKey: syncKey,
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
    );
    final scopeId = store.syncStateScopeId(config);
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(false);
    await store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );
    await store.writeManagedVaultMediaUploadPending(
      scopeId: scopeId,
      pending: true,
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRecordingBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(engine, isNotNull);
      expect(
        engine!.writeGate.value.kind,
        SyncWriteGateKind.localRepairRequired,
      );

      await engine!.syncRunner.push(config);

      expect(backend.managedVaultPushCalls, 1);
      expect(
        await store.readBackgroundSyncRepairRequired(
          backendType: SyncBackendType.managedVault,
          scopeId: scopeId,
        ),
        isTrue,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault pull-side recovery blockers persist repair blocks and gate state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultPullRecoveryBlockedBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPullCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(engine, isNotNull);
      expect(backend.managedVaultPullCalls, greaterThanOrEqualTo(1));
      expect(
        engine!.writeGate.value.kind,
        SyncWriteGateKind.localRepairRequired,
      );
      expect(
        await store.readBackgroundSyncRepairRequired(
          backendType: SyncBackendType.managedVault,
          scopeId: store.syncStateScopeId(
            SyncConfig.managedVault(
              syncKey: syncKey,
              vaultId: 'vault-1',
              baseUrl: 'https://vault.example.com',
            ),
          ),
        ),
        isTrue,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault media uploads stay pending across pulls until the queue is clear',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);
    final pendingScopeId = store.syncStateScopeId(
      SyncConfig.managedVault(
        syncKey: syncKey,
        vaultId: 'vault-1',
        baseUrl: 'https://vault.example.com',
      ),
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRetryingUploadBackend(
        dueBackups: [
          const CloudMediaBackup(
            attachmentSha256: 'a',
            desiredVariant: 'original',
            byteLen: 0,
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            updatedAtMs: 0,
          ),
        ],
      );
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls < 1 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultUploadAttachmentCalls, 1);
      expect(backend.markUploadedCalls, 0);
      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isTrue,
      );

      engine!.triggerPullNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls < 2 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPullCalls, greaterThanOrEqualTo(2));
      expect(backend.managedVaultUploadAttachmentCalls, 2);
      expect(backend.markUploadedCalls, 1);
      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isFalse,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault media uploads remain pending while media backup is disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);
    final pendingScopeId = store.syncStateScopeId(
      SyncConfig.managedVault(
        syncKey: syncKey,
        vaultId: 'vault-1',
        baseUrl: 'https://vault.example.com',
      ),
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRetryingUploadBackend(
        dueBackups: [
          const CloudMediaBackup(
            attachmentSha256: 'a',
            desiredVariant: 'original',
            byteLen: 0,
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            updatedAtMs: 0,
          ),
        ],
      );
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls < 1 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isTrue,
      );

      await store.writeCloudMediaBackupEnabled(false);
      engine!.triggerPullNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPullCalls < 2 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultUploadAttachmentCalls, 1);
      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isTrue,
      );

      await store.writeCloudMediaBackupEnabled(true);
      engine!.triggerPullNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls < 2 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultUploadAttachmentCalls, 2);
      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isFalse,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault pull repairs a missing pending flag from media summary',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(false);
    await store.writeCloudMediaBackupWifiOnly(true);
    final pendingScopeId = store.syncStateScopeId(
      SyncConfig.managedVault(
        syncKey: syncKey,
        vaultId: 'vault-1',
        baseUrl: 'https://vault.example.com',
      ),
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRetryingUploadBackend(
        dueBackups: [
          const CloudMediaBackup(
            attachmentSha256: 'a',
            desiredVariant: 'original',
            byteLen: 0,
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            updatedAtMs: 0,
          ),
        ],
      );
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SyncEngineGate(
                  child: Builder(
                    builder: (context) {
                      engine = SyncEngineScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPullCalls < 1 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isTrue,
      );

      await store.writeCloudMediaBackupEnabled(true);
      await store.writeManagedVaultMediaUploadPending(
        scopeId: pendingScopeId,
        pending: false,
      );

      engine!.triggerPullNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls < 1 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultUploadAttachmentCalls, 1);
      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isTrue,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });
}
