part of 'sync_settings_page_test.dart';

void registerSyncSettingsPageCoreBTests() {
  testWidgets('Manual Pull notifies sync listeners when ops were applied',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _SyncSettingsBackend(webdavPullResult: 1);

    final runner = _FakeRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => _webdavConfig(),
      pushDebounce: const Duration(milliseconds: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    var changeNotifications = 0;
    engine.changes.addListener(() => changeNotifications += 1);

    await tester.pumpWidget(wrapWithI18n(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
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

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await _ensureListItemVisible(tester, downloadButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(downloadButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(changeNotifications, 1);
    engine.stop();
  });

  testWidgets('Manual Download refreshes chat even when pull reports 0 changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _ManualPullUpdatesMessagesBackend();
    final engine = SyncEngine(
      syncRunner: _FakeRunner(),
      loadConfig: () async => _webdavConfig(),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    const conversation = Conversation(
      id: 'loop_home',
      title: 'Loop',
      createdAtMs: 0,
      updatedAtMs: 0,
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: SyncEngineScope(
            engine: engine,
            child: wrapWithI18n(
              const MaterialApp(
                home: ChatPage(conversation: conversation),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No messages yet'), findsOneWidget);

    final chatContext = tester.element(find.byType(ChatPage));
    // ignore: discarded_futures
    Navigator.of(chatContext).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: SyncSettingsPage(configStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await _ensureListItemVisible(tester, downloadButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(downloadButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('hello from device A'), findsOneWidget);
    engine.stop();
  });

  testWidgets('Cloud Download shows up-to-date message when no new changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _SyncSettingsBackend(managedVaultPullResult: 0);
    final cloudAuth = _FakeCloudAuthController();

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

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await _ensureListItemVisible(tester, downloadButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(downloadButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('No new changes'), findsOneWidget);
  });

  testWidgets('Sync settings separates security and manual actions sections',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final backend = _SyncSettingsBackend();

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

    await _ensureListItemVisible(tester, find.text('Security'));
    expect(find.text('Security'), findsOneWidget);

    await _ensureListItemVisible(
      tester,
      find.text('Manual sync & maintenance'),
    );
    expect(find.text('Manual sync & maintenance'), findsOneWidget);
    expect(find.text('Security & manual sync'), findsNothing);
  });

  testWidgets('Managed Vault hides security section', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    final backend = _SyncSettingsBackend();
    final cloudAuth = _FakeCloudAuthController();

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

    expect(find.text('Security'), findsNothing);
    expect(find.byKey(const ValueKey('sync_save_button')), findsOneWidget);
  });

  testWidgets('Manual Upload/Download shows progress indicator',
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

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
    await tester.pump();

    expect(tester.widget<OutlinedButton>(uploadButton).onPressed, isNull);
    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_manual_progress_percent')),
        findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('0%'), findsNothing);

    pushCompleter.complete(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);
    expect(find.byKey(const ValueKey('sync_manual_progress_percent')),
        findsNothing);

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await tester.dragUntilVisible(
      downloadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(downloadButton);
    await tester.pump();

    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_manual_progress_percent')),
        findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('0%'), findsNothing);

    pullCompleter.complete(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);
    expect(find.byKey(const ValueKey('sync_manual_progress_percent')),
        findsNothing);
  });

  testWidgets(
      'manual download progress does not move backwards when total grows',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final progressController = StreamController<String>();
    final backend = _DelayedSyncBackend(
      pushCompleter: Completer<int>(),
      pullCompleter: Completer<int>(),
      webdavPullProgressStream: progressController.stream,
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

    final scrollable = find.byType(ListView);
    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await tester.dragUntilVisible(
      downloadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(downloadButton);
    await tester.pump();

    progressController.add('{"type":"progress","done":1,"total":1}');
    await tester.pump();
    expect(find.text('98%'), findsOneWidget);

    progressController.add('{"type":"progress","done":1,"total":2}');
    await tester.pump();
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('50%'), findsNothing);

    progressController.add('{"type":"result","count":1}');
    await progressController.close();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);
  });

  testWidgets(
      'managed vault manual upload converges with pull before finishing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final pushCompleter = Completer<int>();
    final pullCompleter = Completer<int>();
    final backend = _DelayedManagedVaultSyncBackend(
      pullCompleter: pullCompleter,
      pushCompleter: pushCompleter,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: _FakeCloudAuthController(),
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
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
    await tester.pump();

    expect(backend.calls, <String>['syncManagedVaultPush']);
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsOneWidget);

    pushCompleter.complete(0);
    await tester.pump();

    expect(
      backend.calls,
      <String>['syncManagedVaultPush', 'syncManagedVaultPull'],
    );
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsOneWidget);

    pullCompleter.complete(0);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);
  });

  testWidgets(
      'managed vault manual upload retries push after pull recovers generation mismatch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _GenerationMismatchRecoveryManagedVaultSyncBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: _FakeCloudAuthController(),
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
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
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
    expect(find.text('Uploaded 1 changes'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);
  });

  testWidgets(
      'managed vault manual upload notifies listeners after recovery pull',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _GenerationMismatchRecoveryManagedVaultSyncBackend();
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var notifications = 0;
    engine.changes.addListener(() => notifications++);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: _FakeCloudAuthController(),
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

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
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
    expect(notifications, 1);
    engine.stop();
  });

  testWidgets(
      'managed vault manual upload clears background repair block after success',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
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
        retryCount: 3,
        nextAllowedAtMs: 999999,
        updatedAtMs: 999000,
        lastStatusCode: 503,
        lastErrorCode: 'server_error',
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );

    final backend = _GenerationMismatchRecoveryManagedVaultSyncBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: _FakeCloudAuthController(),
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
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
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

  testWidgets(
      'managed vault manual upload persists repair block when local changes still need upload',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    final scopeId = store.syncStateScopeIdForFields(
      backendType: SyncBackendType.managedVault,
      baseUrl: 'https://vault.example.com',
      remoteRoot: 'uid_1',
      syncKey: Uint8List.fromList(List<int>.filled(32, 9)),
    );

    final backend =
        _LocalUnpushedChangesRecoveryBlockedManagedVaultSyncBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: _FakeCloudAuthController(),
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
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
    await tester.pumpAndSettle();

    expect(backend.calls, <String>['syncManagedVaultPush']);
    expect(
      await store.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeId,
      ),
      isTrue,
    );
  });

  testWidgets('delete local data confirms before resetting synced local data',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _ResetLocalDataSyncSettingsBackend();

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

    final deleteButton = find.text('Delete local data');
    await _ensureListItemVisible(tester, deleteButton);
    expect(deleteButton, findsOneWidget);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Delete local data?'), findsOneWidget);
    expect(backend.resetCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete local data?'), findsNothing);
    expect(backend.resetCalls, 0);
  });

  testWidgets(
      'delete local data resets synced local data and notifies listeners after confirmation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _ResetLocalDataSyncSettingsBackend();
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var notifications = 0;
    engine.changes.addListener(() => notifications++);

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

    final deleteButton = find.text('Delete local data');
    await _ensureListItemVisible(tester, deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete local data again?'), findsOneWidget);
    expect(backend.resetCalls, 0);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete local data?'), findsNothing);
    expect(find.text('Delete local data again?'), findsNothing);
    expect(backend.resetCalls, 1);
    expect(notifications, 1);
    expect(find.text('Local synced data deleted'), findsOneWidget);

    engine.stop();
  });
}
