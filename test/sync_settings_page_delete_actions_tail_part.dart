part of 'sync_settings_page_delete_actions_test.dart';

void registerDeleteActionsTailTests() {
  testWidgets('delete local data disables auto sync and stops sync engine',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
    final engine = SyncEngine(
      syncRunner: _CountingSyncRunner(),
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

    final button = find.widgetWithText(OutlinedButton, 'Delete local data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.resetLocalDataCalls, 1);
    expect(await store.readAutoEnabled(), isFalse);
    expect(engine.isRunning, isFalse);
  });

  testWidgets(
      'delete all data refreshes background schedule with the active config store',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final methodCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(
          'be.tramckrijte.workmanager/foreground_channel_work_manager'),
      (call) async {
        methodCalls.add(call);
        return true;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(
            'be.tramckrijte.workmanager/foreground_channel_work_manager'),
        null,
      );
    });

    final store = SyncConfigStore(scopeKey: 'delete-actions-scope');
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('ScopedRoot');
    await store.writeWebdavBaseUrl('https://scoped.example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend(
      savedSessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
    );
    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 50));

    expect(
      methodCalls.where((call) => call.method == 'registerPeriodicTask'),
      hasLength(1),
    );
    expect(
      methodCalls.where((call) => call.method == 'cancelTaskByUniqueName'),
      isEmpty,
    );
  });

  testWidgets(
      'cloud session model persists canonical managed vault config on load',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    await tester.pumpWidget(
      _wrap(
        backend: _DeleteActionsBackend(),
        store: store,
        cloudAuthController: _FakeCloudAuthController(),
        capabilities: AppPlatformCapabilities.webCloud(),
      ),
    );
    await tester.pumpAndSettle();

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.backendType, SyncBackendType.managedVault);
    expect(configured.remoteRoot, 'uid_1');
    expect(configured.baseUrl, 'https://vault.default.example');
  });

  testWidgets(
      'cloud session model persists canonical managed vault config after auth controller updates',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final methodCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(
          'be.tramckrijte.workmanager/foreground_channel_work_manager'),
      (call) async {
        methodCalls.add(call);
        return true;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(
            'be.tramckrijte.workmanager/foreground_channel_work_manager'),
        null,
      );
    });

    final store = SyncConfigStore(
      scopeKey: 'cloud-session-scope',
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    final cloudAuthController =
        _MutableCloudAuthController(userId: null, idToken: null);

    await tester.pumpWidget(
      _wrap(
        backend: _DeleteActionsBackend(
          savedSessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
        ),
        store: store,
        cloudAuthController: cloudAuthController,
        capabilities: AppPlatformCapabilities.webCloud(),
      ),
    );
    await tester.pumpAndSettle();

    expect(await store.loadConfiguredSync(), isNull);
    await store.writeAutoEnabled(true);
    methodCalls.clear();

    cloudAuthController.setSession(userId: 'uid_2', idToken: 'token-2');
    await tester.pumpAndSettle();

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.backendType, SyncBackendType.managedVault);
    expect(configured.remoteRoot, 'uid_2');
    expect(configured.baseUrl, 'https://vault.default.example');
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      methodCalls.where((call) => call.method == 'registerPeriodicTask'),
      hasLength(1),
    );
  });
}
