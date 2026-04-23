part of 'sync_settings_page_delete_actions_test.dart';

void registerDeleteActionsRegressionTests() {
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
}
