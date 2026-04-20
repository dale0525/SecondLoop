part of 'sync_engine_gate_media_uploads_test.dart';

void registerSyncEngineGateMediaUploadGateStateTests() {
  testWidgets('SyncEngineGate rebuild swaps managed-vault auth token source',
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
      final backend = _ManagedVaultTokenRecordingBackend();
      final authA = _MutableCloudAuthController(
        uidValue: 'uid-1',
        tokenValue: 'token-a',
      );
      final authB = _MutableCloudAuthController(
        uidValue: 'uid-1',
        tokenValue: 'token-b',
      );
      SyncEngine? engine;

      Widget buildApp(CloudAuthController controller) {
        return MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: controller,
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
      }

      await tester.pumpWidget(buildApp(authA));
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPushTokens.isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushTokens, contains('token-a'));

      await tester.pumpWidget(buildApp(authB));
      await tester.pump();

      engine!.triggerPushNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!backend.managedVaultPushTokens.contains('token-b') &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushTokens.last, 'token-b');
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Entitled subscription reopens payment gates, but not grace or storage quota gates',
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
      final backend = _ManagedVaultRecordingBackend();
      final subscription = _FakeSubscriptionStatusController(
        SubscriptionStatus.unknown,
      );
      SyncEngine? engine;

      Widget buildApp() {
        return MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SubscriptionScope(
                  controller: subscription,
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
      }

      await tester.pumpWidget(buildApp());
      await tester.pump();

      engine!.writeGate.value =
          const SyncWriteGateState.graceReadOnly(9999999999999);

      subscription.status = SubscriptionStatus.entitled;
      await tester.pump();

      expect(engine!.writeGate.value.kind, SyncWriteGateKind.graceReadOnly);

      engine!.writeGate.value = const SyncWriteGateState.paymentRequired();
      subscription.status = SubscriptionStatus.unknown;
      await tester.pump();
      subscription.status = SubscriptionStatus.entitled;
      await tester.pump();

      expect(engine!.writeGate.value.kind, SyncWriteGateKind.open);

      engine!.writeGate.value = const SyncWriteGateState.storageQuotaExceeded(
        usedBytes: 50,
        limitBytes: 50,
      );
      subscription.status = SubscriptionStatus.unknown;
      await tester.pump();
      subscription.status = SubscriptionStatus.entitled;
      await tester.pump();

      expect(
        engine!.writeGate.value.kind,
        SyncWriteGateKind.storageQuotaExceeded,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });
}
