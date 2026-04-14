import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/navigation/inherited_scope_page_wrapper.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import '../../test_backend.dart';
import '../../test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'Sync settings forces SecondLoop Cloud and skips sync key derivation for web capabilities',
      (tester) async {
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://web.secondloop.invalid/',
    );
    await store.writeBackendType(SyncBackendType.webdav);

    final backend = _CountingWebSyncBackend();

    await tester.pumpWidget(
      _buildSyncSettingsApp(
        backend: backend,
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sync method'), findsNothing);
    expect(find.text('WebDAV (your server)'), findsNothing);
    expect(find.text('Folder on this computer (desktop)'), findsNothing);
    expect(find.text('SecondLoop Cloud'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('sync_save_button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(backend.deriveSyncKeyCalls, 0);
    expect(backend.managedVaultPullCalls, 0);
    expect(backend.managedVaultPushCalls, 0);
    expect(find.textContaining('unsupported operation'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Upload'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Upload'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Download'), findsOneWidget);
  });

  testWidgets(
      'web capability routes keep pushed settings pages within content width on wide screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://web.secondloop.invalid/',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    await tester.pumpWidget(
      AppPlatformCapabilityScope(
        capabilities: AppPlatformCapabilities.webCloud(),
        child: AppBackendScope(
          backend: TestAppBackend(),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () {
                          pushPageWithInheritedScopes(
                            Navigator.of(context),
                            context,
                            SyncSettingsPage(configStore: store),
                          );
                        },
                        child: const Text('Open sync settings'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open sync settings'));
    await tester.pumpAndSettle();

    final constrainedRoute = find.ancestor(
      of: find.byType(SyncSettingsPage),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox && widget.constraints.maxWidth == 1120,
      ),
    );

    expect(constrainedRoute, findsOneWidget);
    expect(tester.getRect(constrainedRoute).width, lessThanOrEqualTo(1120));
  });
}

Widget _buildSyncSettingsApp({
  required AppBackend backend,
  required SyncConfigStore store,
}) {
  return AppPlatformCapabilityScope(
    capabilities: AppPlatformCapabilities.webCloud(),
    child: AppBackendScope(
      backend: backend,
      child: CloudAuthScope(
        controller: _FakeCloudAuthController(),
        gatewayConfig: const CloudGatewayConfig(
          baseUrl: 'https://web.secondloop.invalid/',
          modelName: 'cloud',
        ),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            MaterialApp(
              home: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  @override
  String? get uid => 'web-user-1';

  @override
  String? get email => 'user@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'web-token';

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

final class _CountingWebSyncBackend extends TestAppBackend {
  int deriveSyncKeyCalls = 0;
  int managedVaultPullCalls = 0;
  int managedVaultPushCalls = 0;

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    deriveSyncKeyCalls += 1;
    return super.deriveSyncKey(passphrase);
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPullCalls += 1;
    return 0;
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls += 1;
    return 0;
  }
}
