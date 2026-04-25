part of 'sync_settings_page_test.dart';

void registerSyncSettingsPageCoreCTests() {
  testWidgets('Save restarts a stopped engine after the page unmounts',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final runner = _BlockingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: store.loadConfiguredSync,
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();
    engine.triggerPushNow();
    await runner.pushStarted.future;

    await tester.pumpWidget(_wrap(
      backend: _SyncSettingsBackend(),
      store: store,
      engine: engine,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder name',
      ),
      'SecondLoop2',
    );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge local and remote'));
    await tester.pump();

    expect(engine.isRunning, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    runner.completePush();
    await tester.pumpAndSettle();

    expect(engine.isRunning, isTrue);
    engine.stopImmediately();
  });

  testWidgets('Failed WebDAV replace-remote after clear pauses new config',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final oldSyncKey = Uint8List.fromList(List<int>.filled(32, 7));
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://old.example.com/dav');
    await store.writeAutoEnabled(true);
    await store.writeSyncKey(oldSyncKey);

    final engine = SyncEngine(
      syncRunner: _FakeRunner(),
      loadConfig: store.loadConfiguredSync,
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();
    final backend = _FailingPushAfterClearRemoteSyncSettingsBackend();
    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: engine,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://new.example.com/dav',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder name',
      ),
      'SecondLoop2',
    );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace remote with this device'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'webdavTest',
      'webdavClear:SecondLoop2',
      'webdavPush:SecondLoop2',
    ]);
    expect(await store.readWebdavBaseUrl(), 'https://new.example.com/dav');
    expect(await store.readRemoteRoot(), 'SecondLoop2');
    expect(await store.readAutoEnabled(), isFalse);
    expect(engine.isRunning, isFalse);
    expect(find.textContaining('webdav_push_failed'), findsOneWidget);
  });

  testWidgets(
      'Failed local folder replace-remote after clear pauses new config',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final oldSyncKey = Uint8List.fromList(List<int>.filled(32, 7));
    await store.writeBackendType(SyncBackendType.localDir);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeLocalDir('/tmp/old-loop');
    await store.writeAutoEnabled(true);
    await store.writeSyncKey(oldSyncKey);

    final engine = SyncEngine(
      syncRunner: _FakeRunner(),
      loadConfig: store.loadConfiguredSync,
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();
    final backend = _FailingLocalDirPushAfterClearRemoteSyncSettingsBackend();
    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: engine,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder path',
      ),
      '/tmp/new-loop',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder name',
      ),
      'SecondLoop2',
    );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace remote with this device'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'localdirTest:SecondLoop2',
      'localdirClear:SecondLoop2',
      'localdirPush:SecondLoop2',
    ]);
    expect(await store.readBackendType(), SyncBackendType.localDir);
    expect(await store.readLocalDir(), '/tmp/new-loop');
    expect(await store.readRemoteRoot(), 'SecondLoop2');
    expect(await store.readAutoEnabled(), isFalse);
    expect(engine.isRunning, isFalse);
    expect(find.textContaining('localdir_push_failed'), findsOneWidget);
  });

  testWidgets('WebDAV replace-remote uploads cloud media backup after clear',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    addTearDown(() => ConnectivityPlatform.instance = oldConnectivity);

    final store = SyncConfigStore();
    final oldSyncKey = Uint8List.fromList(List<int>.filled(32, 7));
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://old.example.com/dav');
    await store.writeAutoEnabled(true);
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);
    await store.writeSyncKey(oldSyncKey);

    final backend = _MediaBackupReplaceRemoteWebdavBackend();
    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://new.example.com/dav',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder name',
      ),
      'SecondLoop2',
    );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace remote with this device'));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      containsAllInOrder(<String>[
        'webdavTest',
        'webdavClear:SecondLoop2',
        'webdavPush:SecondLoop2',
        'uploadMedia:SecondLoop2:sha-media-1',
      ]),
    );
  });

  testWidgets('Failed local folder replace-local restores snapshot and config',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final oldSyncKey = Uint8List.fromList(List<int>.filled(32, 7));
    await store.writeBackendType(SyncBackendType.localDir);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeLocalDir('/tmp/old-loop');
    await store.writeSyncKey(oldSyncKey);

    final backend = _FailingLocalDirReplaceLocalSyncSettingsBackend();
    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder path',
      ),
      '/tmp/new-loop',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder name',
      ),
      'SecondLoop2',
    );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace this device with remote'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'localdirTest:SecondLoop2',
      'createSnapshot',
      'resetLocal',
      'localdirPull:SecondLoop2',
      'restoreSnapshot:snapshot-1',
    ]);
    expect(await store.readBackendType(), SyncBackendType.localDir);
    expect(await store.readLocalDir(), '/tmp/old-loop');
    expect(await store.readRemoteRoot(), 'SecondLoop');
    expect(await store.readSyncKey(), oldSyncKey);
  });
}

final class _BlockingSyncRunner implements SyncRunner {
  final Completer<void> pushStarted = Completer<void>();
  final Completer<void> _pushCompleter = Completer<void>();

  void completePush() {
    if (!_pushCompleter.isCompleted) {
      _pushCompleter.complete();
    }
  }

  @override
  Future<int> push(SyncConfig config) async {
    if (!pushStarted.isCompleted) {
      pushStarted.complete();
    }
    await _pushCompleter.future;
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async => 0;
}
