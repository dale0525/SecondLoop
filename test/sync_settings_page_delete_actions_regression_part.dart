part of 'sync_settings_page_delete_actions_test.dart';

void registerDeleteActionsRegressionTests() {
  testWidgets(
      'delete all data aborts local reset when auto sync cannot be disabled after remote timeout',
      (tester) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    final prefsStore = _ToggleFailingPrefsStore();
    SharedPreferencesStorePlatform.instance = prefsStore;
    addTearDown(() {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend(
      webdavClearRemoteRootError: TimeoutException('operation timeout'),
    );
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    prefsStore.failPublicConfigWrites = true;
    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 0);
    expect(await store.readAutoEnabled(), isTrue);
    expect(engine.isRunning, isFalse);
    expect(find.textContaining('Delete failed:'), findsOneWidget);
    expect(
      find.textContaining('injected prefs write failure'),
      findsOneWidget,
    );
  });

  testWidgets('delete all data aborts when sync engine stop times out',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
    final runner = _BlockingPullRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: true,
      pushDebounce: Duration.zero,
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
    )..start();
    await tester.pump();
    expect(runner.pullCalls, 1);

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(backend.syncWebdavClearRemoteRootCalls, 0);
    expect(backend.resetLocalDataCalls, 0);
    expect(find.textContaining('Delete failed:'), findsOneWidget);
    expect(find.textContaining('sync engine did not stop'), findsOneWidget);

    runner.completePull(applied: 0);
    await tester.pump();
  });

  testWidgets(
      'delete all data keeps sync stopped when remote clear succeeded but local reset failed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend(
      resetLocalDataError: StateError('local reset failed'),
    );
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
    expect(await store.readAutoEnabled(), isFalse);
    expect(engine.isRunning, isFalse);
    expect(
      find.textContaining('Remote sync data deleted, but local cleanup failed'),
      findsOneWidget,
    );

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);
  });

  testWidgets(
      'delete all data treats timeout-like error messages as local-only deletion',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend(
      webdavClearRemoteRootError: StateError('operation timeout'),
    );
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
    expect(await store.readAutoEnabled(), isFalse);
    expect(engine.isRunning, isFalse);
    expect(find.textContaining('Deleted local data only'), findsOneWidget);

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);
  });

  testWidgets(
      'delete all data keeps sync stopped when remote timeout and local reset failed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend(
      webdavClearRemoteRootError: TimeoutException('operation timeout'),
      resetLocalDataError: StateError('local reset failed'),
    );
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
    expect(await store.readAutoEnabled(), isFalse);
    expect(engine.isRunning, isFalse);
    expect(find.textContaining('Remote clear timed out'), findsOneWidget);
    expect(find.textContaining('local cleanup failed'), findsOneWidget);

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);
  });
}
