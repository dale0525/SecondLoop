part of 'sync_settings_page_test.dart';

void registerSyncSettingsPageCoreATests() {
  testWidgets('removes Test connection button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final backend = _SyncSettingsBackend();

    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('Test connection'), findsNothing);
  });

  testWidgets('configured recovery passphrase shows masked placeholder',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    final backend = _SyncSettingsBackend();

    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final passphraseField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Recovery passphrase (Advanced)',
    );
    final field = tester.widget<TextField>(passphraseField);
    expect(field.controller?.text, isNotEmpty);
  });

  testWidgets('Save runs connection test and triggers sync on success',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final pushCompleter = Completer<int>();
    final pullCompleter = Completer<int>();
    final backend = _DelayedSyncBackend(
      pushCompleter: pushCompleter,
      pullCompleter: pullCompleter,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Recovery passphrase (Advanced)',
      ),
      'passphrase',
    );

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pump();

    expect(backend.webdavTestCalls, 1);
    expect(find.byKey(const ValueKey('sync_save_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_save_progress_percent')),
        findsOneWidget);

    pullCompleter.complete(0);
    await tester.pumpAndSettle();
    // Still waiting for push.
    expect(find.byKey(const ValueKey('sync_save_progress')), findsOneWidget);

    pushCompleter.complete(0);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync_save_progress')), findsNothing);
    expect(
        find.byKey(const ValueKey('sync_save_progress_percent')), findsNothing);

    expect(find.textContaining('Connection'), findsOneWidget);
  });

  testWidgets('Save after changing WebDAV folder shows sync progress dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final pushCompleter = Completer<int>();
    final pullCompleter = Completer<int>();
    final backend = _DelayedSyncBackend(
      pushCompleter: pushCompleter,
      pullCompleter: pullCompleter,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Change "Folder name".
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder name',
      ),
      'SecondLoop2',
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge local and remote'));
    await tester.pump();

    expect(find.byKey(const ValueKey('sync_save_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_save_progress_percent')),
        findsOneWidget);

    pushCompleter.complete(0);
    await tester.pumpAndSettle();
    pullCompleter.complete(0);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync_save_progress')), findsNothing);
  });

  testWidgets('Save after changing WebDAV folder asks how to reconcile data',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _SyncSettingsBackend();
    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
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
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Choose sync direction'), findsOneWidget);
    expect(find.text('Replace remote with this device'), findsOneWidget);
    expect(find.text('Replace this device with remote'), findsOneWidget);
    expect(find.text('Merge local and remote'), findsOneWidget);
  });

  testWidgets('Save can replace local data from new WebDAV folder',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _TrackingSyncSettingsBackend();
    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
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
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace this device with remote'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'webdavTest',
      'resetLocal',
      'webdavPull:SecondLoop2',
    ]);
  });

  testWidgets(
      'Failed WebDAV replace-local restores local snapshot and old config',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final oldSyncKey = Uint8List.fromList(List<int>.filled(32, 7));
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://old.example.com/dav');
    await store.writeWebdavUsername('old-user');
    await store.writeWebdavPassword('old-password');
    await store.writeSyncKey(oldSyncKey);

    final backend = _FailingReplaceLocalSyncSettingsBackend();
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

    await tester.tap(find.text('Replace this device with remote'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'webdavTest',
      'createSnapshot',
      'resetLocal',
      'webdavPull:SecondLoop2',
      'restoreSnapshot:snapshot-1',
    ]);
    expect(await store.readBackendType(), SyncBackendType.webdav);
    expect(await store.readWebdavBaseUrl(), 'https://old.example.com/dav');
    expect(await store.readWebdavUsername(), 'old-user');
    expect(await store.readWebdavPassword(), 'old-password');
    expect(await store.readRemoteRoot(), 'SecondLoop');
    expect(await store.readSyncKey(), oldSyncKey);
  });

  testWidgets('Save after changing local folder shows sync progress dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.localDir);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeLocalDir('/tmp/SecondLoopVault');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final pushCompleter = Completer<int>();
    final pullCompleter = Completer<int>();
    final backend = _DelayedLocalDirSyncBackend(
      pushCompleter: pushCompleter,
      pullCompleter: pullCompleter,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder path',
      ),
      '/tmp/SecondLoopVault2',
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge local and remote'));
    await tester.pump();

    expect(find.byKey(const ValueKey('sync_save_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_save_progress_percent')),
        findsOneWidget);

    pullCompleter.complete(0);
    await tester.pumpAndSettle();
    pushCompleter.complete(0);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync_save_progress')), findsNothing);
  });

  testWidgets('Switch to Cloud sync triggers sync progress on Save',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final pullCompleter = Completer<int>();
    final pushCompleter = Completer<int>();
    final backend = _DelayedManagedVaultSyncBackend(
      pullCompleter: pullCompleter,
      pushCompleter: pushCompleter,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: Scaffold(
                  body: SyncSettingsPage(configStore: store),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Change backend to Cloud.
    await tester.tap(find.byType(DropdownButtonFormField<SyncBackendType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SecondLoop Cloud').last);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge local and remote'));
    await tester.pump();

    expect(find.byKey(const ValueKey('sync_save_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_save_progress_percent')),
        findsOneWidget);

    expect(backend.calls, <String>['syncManagedVaultPush']);

    pushCompleter.complete(0);
    await tester.pumpAndSettle();
    expect(
      backend.calls,
      <String>['syncManagedVaultPush', 'syncManagedVaultPull'],
    );

    pullCompleter.complete(0);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync_save_progress')), findsNothing);
  });

  testWidgets('Save auto-generates sync key when missing (WebDAV)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final backend = _SyncSettingsBackend();

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
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter your recovery passphrase and tap Save first.'),
      findsNothing,
    );
    expect(await store.readWebdavBaseUrl(), 'https://example.com/dav');
    final syncKey = await store.readSyncKey();
    expect(syncKey, isNotNull);
    expect(syncKey!.length, 32);
  });

  testWidgets('Managed Vault save still pulls when push is read-only blocked',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    final backend = _GraceReadOnlyManagedVaultSyncBackend();
    final cloudAuth = _FakeCloudAuthController();
    final engine = SyncEngine(
      syncRunner: _FakeRunner(),
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
            child: CloudAuthScope(
              controller: cloudAuth,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: SyncEngineScope(
                  engine: engine,
                  child: Scaffold(
                    body: SyncSettingsPage(configStore: store),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<SyncBackendType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SecondLoop Cloud').last);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>['syncManagedVaultPush', 'syncManagedVaultPull'],
    );
    expect(find.textContaining('HTTP 403'), findsNothing);
    expect(find.byKey(const ValueKey('sync_save_progress')), findsNothing);
    expect(engine.writeGate.value.kind, SyncWriteGateKind.graceReadOnly);
    engine.stop();
  });

  testWidgets('Save auto-generates sync key when missing (SecondLoop Cloud)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    final backend = _SyncSettingsBackend();
    final cloudAuth = _FakeCloudAuthController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter your recovery passphrase and tap Save first.'),
      findsNothing,
    );
    final syncKey = await store.readSyncKey();
    expect(syncKey, isNotNull);
    expect(syncKey!.length, 32);
  });

  testWidgets(
      'Save prefers recovery envelope over legacy derive when passphrase is provided',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeRecoveryEnvelopeJson(
      '{"version":1,"wrapped_sync_key_b64":"abc","kdf":{"version":1}}',
    );

    final recoveredSyncKey = Uint8List.fromList(List<int>.filled(32, 6));
    final backend = _SyncSettingsBackend(recoveredSyncKey: recoveredSyncKey);

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
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Recovery passphrase (Advanced)',
      ),
      'recover-me',
    );

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(backend.recoverSyncKeyFromEnvelopeCalls, 1);
    expect(backend.deriveSyncKeyCalls, 0);

    final syncKey = await store.readSyncKey();
    expect(syncKey, recoveredSyncKey);
  });

  testWidgets('Managed Vault save does not upload recovery envelope',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    final backend = _SyncSettingsBackend();
    final cloudAuth = _FakeCloudAuthController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              child: Scaffold(
                body: SyncSettingsPage(
                  configStore: store,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(backend.deriveSyncKeyCalls, 1);
    expect(backend.createSyncRecoveryEnvelopeCalls, 0);
    expect(await store.readSyncKey(), isNotNull);
  });

  testWidgets('Managed Vault page load does not auto-fetch recovery envelope',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    final backend = _SyncSettingsBackend();
    final cloudAuth = _FakeCloudAuthController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              child: Scaffold(
                body: SyncSettingsPage(
                  configStore: store,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(await store.readRecoveryEnvelopeJson(), isNull);
  });

  testWidgets('Managed Vault save ignores remote recovery envelope',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    final recoveredSyncKey = Uint8List.fromList(List<int>.filled(32, 4));
    final backend = _SyncSettingsBackend(recoveredSyncKey: recoveredSyncKey);
    final cloudAuth = _FakeCloudAuthController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              child: Scaffold(
                body: SyncSettingsPage(
                  configStore: store,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(backend.recoverSyncKeyFromEnvelopeCalls, 0);
    expect(backend.deriveSyncKeyCalls, 1);
    expect(await store.readSyncKey(), isNot(recoveredSyncKey));
  });
}
