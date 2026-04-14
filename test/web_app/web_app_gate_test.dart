import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/settings/cloud_account_panel.dart';
import 'package:secondloop/web_app/web_app_gate.dart';
import 'package:secondloop/web_app/web_entry_intent.dart';
import 'package:secondloop/web_app/web_formal_settings_adapters.dart';

import '../test_i18n.dart';

class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  _FakeCloudAuthController({
    this.initialUid,
    this.initialEmail,
    this.initialEmailVerified,
  })  : _uid = initialUid,
        _email = initialEmail,
        _emailVerified = initialEmailVerified;

  final String? initialUid;
  final String? initialEmail;
  final bool? initialEmailVerified;
  String? _uid;
  String? _email;
  bool? _emailVerified;

  @override
  String? get uid => _uid;

  @override
  String? get email => _email;

  @override
  bool? get emailVerified => _emailVerified;

  @override
  Future<String?> getIdToken() async => _uid == null ? null : 'token';

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
  }) async {
    _uid = 'uid-1';
    _email = email;
    _emailVerified = false;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _email = null;
    _emailVerified = null;
    notifyListeners();
  }

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _uid = 'uid-2';
    _email = email;
    _emailVerified = false;
    notifyListeners();
  }
}

class _FakeWebAppService extends WebAppService {
  _FakeWebAppService({
    required this.subscription,
    this.checkoutError,
  });

  WebSubscriptionState subscription;
  final Object? checkoutError;

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription({
    required String idToken,
  }) async {
    return WebSubscriptionSnapshot(
      state: subscription,
      canManageSubscription: subscription == WebSubscriptionState.entitled,
    );
  }

  @override
  Future<void> openCheckout({required String idToken}) async {
    if (checkoutError != null) throw checkoutError!;
  }

  @override
  Future<void> openPortal({required String idToken}) async {}
}

Widget _buildApp({
  required ObservableCloudAuthController controller,
  required WebAppService service,
  CloudWebBackend? chatBackend,
  Locale? locale,
  WebEntryIntent entryIntent = WebEntryIntent.open,
  String managedVaultBaseUrl = '',
}) {
  return wrapWithI18n(
    MaterialApp(
      locale: locale,
      home: WebAppGate(
        authController: controller,
        service: service,
        chatBackend: chatBackend,
        entryIntent: entryIntent,
        managedVaultBaseUrl: managedVaultBaseUrl,
      ),
    ),
  );
}

void main() {
  testWidgets('shows auth form when signed out', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(),
        service: _FakeWebAppService(subscription: WebSubscriptionState.unknown),
      ),
    );

    expect(find.byType(CloudAccountPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_up')), findsOneWidget);
  });

  testWidgets('subscribe intent explains sign-in before web access',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(),
        service: _FakeWebAppService(subscription: WebSubscriptionState.unknown),
        entryIntent: WebEntryIntent.subscribe,
      ),
    );

    expect(find.text('Subscribe for web access'), findsOneWidget);
    expect(find.textContaining('Sign in first'), findsOneWidget);
  });

  testWidgets('shows upgrade gate when signed in without entitlement',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.notEntitled),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_subscribe')), findsOneWidget);
  });

  testWidgets('subscription refresh unlocks shared shell after entitlement',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.notEntitled,
    );

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: service,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPanel), findsOneWidget);

    service.subscription = WebSubscriptionState.entitled;
    await tester.tap(find.byKey(const ValueKey('cloud_subscription_refresh')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(CloudAccountPanel), findsNothing);
  });

  testWidgets('upgrade gate localizes checkout payment-required error inline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.notEntitled,
          checkoutError:
              'cloud-gateway request failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final subscribeButton = find.byKey(const ValueKey('cloud_subscribe'));
    await tester.ensureVisible(subscribeButton);
    await tester.pumpAndSettle();
    await tester.tap(subscribeButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text(
        'Failed to load: Cloud sync is paused. Renew your subscription to continue syncing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('upgrade gate localizes checkout missing web api key inline',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.notEntitled,
          checkoutError: FirebaseAuthException('missing_web_api_key'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final subscribeButton = find.byKey(const ValueKey('cloud_subscribe'));
    await tester.ensureVisible(subscribeButton);
    await tester.pumpAndSettle();
    await tester.tap(subscribeButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('missing_web_api_key'), findsNothing);
    expect(
      find.textContaining("Cloud sign-in isn't available in this build."),
      findsOneWidget,
    );
  });

  testWidgets('shows shared shell when signed in and entitled', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.text('Files'), findsNothing);
  });

  testWidgets('wide-screen entitled shell uses a navigation rail',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.text('Files'), findsNothing);
  });

  testWidgets(
      'web gate clears invalid managed vault sync override and falls back to runtime base URL',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.secondloop.example',
    );
    await store.writeManagedVaultBaseUrl(kWebFormalSettingsBaseUrl);

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(),
        service: _FakeWebAppService(subscription: WebSubscriptionState.unknown),
        managedVaultBaseUrl: 'https://vault.secondloop.example',
      ),
    );
    await tester.pumpAndSettle();

    expect(await store.readManagedVaultBaseUrl(), isNull);
    expect(
      await store.resolveManagedVaultBaseUrl(),
      'https://vault.secondloop.example',
    );
  });
}
