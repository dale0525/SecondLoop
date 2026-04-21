part of 'sync_engine_gate_media_uploads_test.dart';

void registerSyncEngineGateMediaUploadWebdavTests() {
  testWidgets('Media uploads off => sync uses ops-only push (WebDAV)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend();

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.webdavPushCalls == 0 &&
            backend.webdavPushOpsOnlyCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.webdavPushCalls, 0);
      expect(backend.webdavPushOpsOnlyCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets('Media uploads on => uploads due items automatically (WebDAV)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend(
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
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.webdavUploadAttachmentCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.webdavPushOpsOnlyCalls, greaterThanOrEqualTo(1));
      expect(backend.webdavUploadAttachmentCalls, 1);
      expect(backend.markUploadedCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'SyncEngineGate flushes pending push when app pauses during blocking pull',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _BlockingLifecycleBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
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
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while ((backend.webdavPullCalls == 0 ||
                backend.webdavPushOpsOnlyCalls == 0) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(engine, isNotNull);
      final baselinePushCalls = backend.webdavPushOpsOnlyCalls;
      expect(baselinePushCalls, greaterThanOrEqualTo(1));

      backend.blockNextPull();
      engine!.triggerPullNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!backend.hasBlockedPull && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(backend.hasBlockedPull, isTrue);

      engine!.notifyLocalMutation();
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      backend.completeBlockedPull(applied: 0);
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.webdavPushOpsOnlyCalls == baselinePushCalls &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.webdavPushOpsOnlyCalls, baselinePushCalls + 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets('Media uploads on => auto-backfills cloud media queue',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend();

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.cloudMediaBackfillCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.cloudMediaBackfillCalls, greaterThanOrEqualTo(1));
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets('Auto sync skips media backfill when the current scope is done',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);
    final scopeId = store.syncStateScopeIdForFields(
      backendType: SyncBackendType.webdav,
      baseUrl: 'https://example.com/dav',
      username: 'u',
      remoteRoot: 'SecondLoop',
      syncKey: syncKey,
    );
    await store.writeCloudMediaBackupBackfillDone(scopeId: scopeId, done: true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend();

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      expect(backend.cloudMediaBackfillCalls, 0);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });
}
