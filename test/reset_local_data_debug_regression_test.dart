import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/creem_billing_client.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/settings/settings_page.dart';
import 'package:secondloop/web_app/web_formal_settings_scope.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Debug reset clears remote data using web formal scoped config',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final defaultRemote = Directory.systemTemp.createTempSync('sl_default_');
    final scopedRemote = Directory.systemTemp.createTempSync('sl_scoped_');
    addTearDown(() => _deleteDir(defaultRemote));
    addTearDown(() => _deleteDir(scopedRemote));

    await _writeLocalDirConfig(
      SyncConfigStore(),
      localDir: defaultRemote.path,
      remoteRoot: 'DefaultRoot',
      syncKeyByte: 2,
    );
    final scopedStore = SyncConfigStore(scopeKey: 'web-native:uid-1');
    await _writeLocalDirConfig(
      scopedStore,
      localDir: scopedRemote.path,
      remoteRoot: 'ScopedRoot',
      syncKeyByte: 3,
    );

    final defaultSentinel = _writeRemoteSentinel(defaultRemote, 'DefaultRoot');
    final scopedSentinel = _writeRemoteSentinel(scopedRemote, 'ScopedRoot');
    final backend = _ResetDebugBackend(deviceId: 'deviceA');
    var locked = false;

    await _pumpSettings(
      tester,
      backend: backend,
      lock: () => locked = true,
      webStore: scopedStore,
    );

    await _tapDebugReset(tester, allDevices: true);
    await _waitUntil(tester, () => locked);

    expect(backend.clearLocalDirCalls, hasLength(1));
    expect(backend.clearLocalDirCalls.single.localDir, scopedRemote.path);
    expect(backend.clearLocalDirCalls.single.remoteRoot, 'ScopedRoot');
    expect(scopedSentinel.existsSync(), isFalse);
    expect(defaultSentinel.existsSync(), isTrue);
  });

  testWidgets(
      'Debug reset waits for in-flight sync before clearing remote data',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final remote = Directory.systemTemp.createTempSync('sl_remote_');
    addTearDown(() => _deleteDir(remote));

    final store = SyncConfigStore();
    await _writeLocalDirConfig(
      store,
      localDir: remote.path,
      remoteRoot: 'RemoteRoot',
      syncKeyByte: 4,
    );
    _writeRemoteSentinel(remote, 'RemoteRoot');

    final pushStarted = Completer<void>();
    final releasePush = Completer<void>();
    var pushCompleted = false;
    final runner = _BlockingSyncRunner(
      onPushStarted: () {
        if (!pushStarted.isCompleted) pushStarted.complete();
      },
      releasePush: releasePush.future,
      onPushCompleted: () => pushCompleted = true,
    );
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: store.loadConfiguredSync,
      pullOnStart: false,
      pushDebounce: Duration.zero,
    );
    addTearDown(engine.stopImmediately);
    engine.start();
    engine.triggerPushNow();
    await tester.runAsync(
      () => pushStarted.future.timeout(const Duration(seconds: 2)),
    );

    var remoteClearStartedBeforePushCompleted = false;
    final backend = _ResetDebugBackend(
      deviceId: 'deviceA',
      onBeforeClearRemoteRoot: () {
        remoteClearStartedBeforePushCompleted = !pushCompleted;
      },
    );
    var locked = false;

    await _pumpSettings(
      tester,
      backend: backend,
      lock: () => locked = true,
      engine: engine,
    );

    await _openDebugResetDialog(tester, allDevices: true);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    expect(backend.clearLocalDirCalls, isEmpty);
    expect(locked, isFalse);

    releasePush.complete();
    await _waitUntil(tester, () => locked);

    expect(backend.clearLocalDirCalls, hasLength(1));
    expect(remoteClearStartedBeforePushCompleted, isFalse);
  });
}

Future<void> _writeLocalDirConfig(
  SyncConfigStore store, {
  required String localDir,
  required String remoteRoot,
  required int syncKeyByte,
}) async {
  await store.writeBackendType(SyncBackendType.localDir);
  await store.writeAutoEnabled(true);
  await store.writeLocalDir(localDir);
  await store.writeRemoteRoot(remoteRoot);
  await store.writeSyncKey(
    Uint8List.fromList(List<int>.filled(32, syncKeyByte)),
  );
}

File _writeRemoteSentinel(Directory baseDir, String remoteRoot) {
  final file = File(
    '${baseDir.path}${Platform.pathSeparator}$remoteRoot'
    '${Platform.pathSeparator}ops${Platform.pathSeparator}op_1.json',
  );
  file.createSync(recursive: true);
  file.writeAsStringSync('{"op_id":"1"}');
  return file;
}

void _deleteDir(Directory dir) {
  try {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {}
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required AppBackend backend,
  required VoidCallback lock,
  SyncEngine? engine,
  SyncConfigStore? webStore,
}) async {
  Widget page = const Scaffold(body: SettingsPage());
  if (webStore != null) {
    page = WebFormalSettingsScope(
      dependencies: _webFormalDependencies(webStore),
      child: page,
    );
  }
  if (engine != null) {
    page = SyncEngineScope(engine: engine, child: page);
  }

  await tester.pumpWidget(
    AppBackendScope(
      backend: backend,
      child: SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: lock,
        child: wrapWithI18n(MaterialApp(home: page)),
      ),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

Future<void> _tapDebugReset(
  WidgetTester tester, {
  required bool allDevices,
}) async {
  await _openDebugResetDialog(tester, allDevices: allDevices);
  await tester.tap(find.text('Reset'));
  await tester.pump();
}

Future<void> _openDebugResetDialog(
  WidgetTester tester, {
  required bool allDevices,
}) async {
  final label = allDevices
      ? 'Debug: Reset local data (all devices)'
      : 'Debug: Reset local data (this device)';
  await tester.scrollUntilVisible(find.text(label), 200);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
  expect(find.text('Reset local data?'), findsOneWidget);
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}

WebFormalSettingsDependencies _webFormalDependencies(SyncConfigStore store) {
  return WebFormalSettingsDependencies(
    billingClient: _FakeBillingClient(),
    cloudUsageClient: CloudUsageClient(),
    vaultUsageClient: VaultUsageClient(),
    vaultAttachmentsClient: VaultAttachmentsClient(),
    vaultConfigStore: store,
    cloudAuthController: _FakeCloudAuthController(),
    cloudGatewayConfig: const CloudGatewayConfig(
      baseUrl: 'https://vault.example.invalid',
      modelName: 'cloud',
    ),
    subscriptionController: _FakeSubscriptionController(),
    isWebOverride: true,
  );
}

final class _ResetDebugBackend extends TestAppBackend {
  _ResetDebugBackend({
    required this.deviceId,
    this.onBeforeClearRemoteRoot,
  });

  final String deviceId;
  final VoidCallback? onBeforeClearRemoteRoot;
  final List<({String localDir, String remoteRoot})> clearLocalDirCalls = [];

  @override
  Future<String> getOrCreateDeviceId() async => deviceId;

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {
    onBeforeClearRemoteRoot?.call();
    clearLocalDirCalls.add((localDir: localDir, remoteRoot: remoteRoot));
    final dir = Directory('$localDir${Platform.pathSeparator}$remoteRoot');
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

final class _BlockingSyncRunner implements SyncRunner {
  _BlockingSyncRunner({
    required this.onPushStarted,
    required this.releasePush,
    required this.onPushCompleted,
  });

  final VoidCallback onPushStarted;
  final Future<void> releasePush;
  final VoidCallback onPushCompleted;

  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async {
    onPushStarted();
    await releasePush;
    onPushCompleted();
    return 1;
  }
}

final class _FakeBillingClient implements BillingClient {
  @override
  Future<void> openCheckout() async {}

  @override
  Future<void> openPortal() async {}
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  @override
  SubscriptionStatus get status => SubscriptionStatus.entitled;
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  @override
  String? get uid => 'uid-1';

  @override
  String? get email => 'user@example.invalid';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
