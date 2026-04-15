import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/navigation/inherited_scope_page_wrapper.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/creem_billing_client.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/web_app/web_formal_settings_scope.dart';

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

  testWidgets('web cloud backend download action does not throw unimplemented',
      (tester) async {
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://web.secondloop.invalid/',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    await tester.pumpWidget(
      _buildSyncSettingsApp(
        backend: CloudWebBackend(
          chatClient: const UnsupportedCloudWebChatClient(),
        ),
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Download'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Download'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('UnimplementedError'), findsNothing);
    expect(find.textContaining('Download failed'), findsNothing);
    expect(find.text('No new changes'), findsOneWidget);
  });

  testWidgets('web cloud backend upload action does not throw unimplemented',
      (tester) async {
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://web.secondloop.invalid/',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    await tester.pumpWidget(
      _buildSyncSettingsApp(
        backend: CloudWebBackend(
          chatClient: const UnsupportedCloudWebChatClient(),
        ),
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Upload'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Upload'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('UnimplementedError'), findsNothing);
    expect(find.textContaining('Upload failed'), findsNothing);
    expect(find.text('Uploaded 0 changes'), findsOneWidget);
  });

  testWidgets(
      'web sync settings without explicit config store reuses web formal settings vault store',
      (tester) async {
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.runtime.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    await tester.pumpWidget(
      _buildWebFormalSyncSettingsApp(
        backend: CloudWebBackend(
          chatClient: const UnsupportedCloudWebChatClient(),
        ),
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Download'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Download'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('Server address is required'), findsNothing);
    expect(find.text('No new changes'), findsOneWidget);
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

Widget _buildWebFormalSyncSettingsApp({
  required AppBackend backend,
  required SyncConfigStore store,
}) {
  final cloudAuth = _FakeCloudAuthController();
  const cloudGatewayConfig = CloudGatewayConfig(
    baseUrl: 'https://web.secondloop.invalid/',
    modelName: 'cloud',
  );

  return AppPlatformCapabilityScope(
    capabilities: AppPlatformCapabilities.webCloud(),
    child: AppBackendScope(
      backend: backend,
      child: CloudAuthScope(
        controller: cloudAuth,
        gatewayConfig: cloudGatewayConfig,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: WebFormalSettingsScope(
            dependencies: WebFormalSettingsDependencies(
              billingClient: _FakeBillingClient(),
              cloudUsageClient: CloudUsageClient(),
              vaultUsageClient: VaultUsageClient(),
              vaultAttachmentsClient: VaultAttachmentsClient(),
              vaultConfigStore: store,
              cloudAuthController: cloudAuth,
              cloudGatewayConfig: cloudGatewayConfig,
              subscriptionController: _FakeSubscriptionController(),
              isWebOverride: true,
            ),
            child: wrapWithI18n(
              const MaterialApp(
                home: Scaffold(
                  body: SyncSettingsPage(),
                ),
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

final class _FakeBillingClient implements BillingClient {
  @override
  Future<void> openCheckout() async {}

  @override
  Future<void> openPortal() async {}
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  @override
  SubscriptionStatus get status => SubscriptionStatus.unknown;
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
