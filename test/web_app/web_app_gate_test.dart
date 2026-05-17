import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/features/lock/lock_gate.dart';
import 'package:secondloop/features/settings/cloud_account_panel.dart';
import 'package:secondloop/web_app/web_app_gate.dart';
import 'package:secondloop/web_app/web_entry_intent.dart';
import 'package:secondloop/web_app/web_formal_settings_adapters.dart';
import 'package:secondloop/web_app/web_initial_sync_gate.dart';
import 'package:secondloop/web_app/web_native_app_backend.dart';
import 'package:secondloop/web_app/web_public_entry_scaffold.dart';

import '../test_i18n.dart';
import '../test_backend.dart';

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

  void setSession({
    String? uid,
    String? email,
    bool? emailVerified,
  }) {
    _uid = uid;
    _email = email;
    _emailVerified = emailVerified;
    notifyListeners();
  }

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

final class _FakeUnlockedWebBackend extends TestAppBackend {
  @override
  Future<bool> isMasterPasswordSet() async => false;
}

final class _InitRequiredWebBackend extends TestAppBackend {
  int initCalls = 0;
  bool _initialized = false;

  @override
  Future<void> init() async {
    initCalls += 1;
    _initialized = true;
  }

  @override
  Future<bool> isMasterPasswordSet() async {
    if (!_initialized) {
      throw StateError('backend has not been initialized');
    }
    return false;
  }
}

Widget _buildApp({
  required ObservableCloudAuthController controller,
  required WebAppService service,
  AppBackend? backend,
  Locale? locale,
  WebEntryIntent entryIntent = WebEntryIntent.open,
  String managedVaultBaseUrl = '',
  bool injectTestBackend = true,
  Future<void> Function(SyncConfigStore store)? syncDefaultsPrimer,
  Duration syncDefaultsPrimingTimeout = const Duration(seconds: 2),
}) {
  return wrapWithI18n(
    MaterialApp(
      locale: locale,
      home: WebAppGate(
        authController: controller,
        service: service,
        backend:
            backend ?? (injectTestBackend ? _FakeUnlockedWebBackend() : null),
        entryIntent: entryIntent,
        managedVaultBaseUrl: managedVaultBaseUrl,
        syncDefaultsPrimer: syncDefaultsPrimer,
        syncDefaultsPrimingTimeout: syncDefaultsPrimingTimeout,
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

    expect(find.byType(CloudAccountPanel), findsNothing);
    await tester.pumpAndSettle();

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

    expect(find.text('Subscribe for web access'), findsNothing);
    await tester.pumpAndSettle();

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
    expect(find.byType(AgentConversationPage), findsOneWidget);
    expect(find.text('Files'), findsNothing);
  });

  testWidgets('entitled web app boots through lock and initial sync gates',
      (tester) async {
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

    expect(find.byType(LockGate), findsOneWidget);
    expect(find.byType(WebInitialSyncGate), findsOneWidget);
  });

  testWidgets('entitled web app initializes backend before lock gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _InitRequiredWebBackend();

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        backend: backend,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(backend.initCalls, 1);
    expect(find.byType(AppShell), findsOneWidget);
    expect(
      find.textContaining('backend has not been initialized'),
      findsNothing,
    );
  });

  testWidgets('web gate provisions WebNativeAppBackend by default',
      (tester) async {
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        injectTestBackend: false,
      ),
    );
    await tester.pump();

    final backendScope =
        tester.widget<AppBackendScope>(find.byType(AppBackendScope).first);
    expect(backendScope.backend, isA<WebNativeAppBackend>());
  });

  testWidgets('wide-screen entitled shell uses the agent sidebar',
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

    expect(find.byKey(const ValueKey('app_shell_sidebar')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(AgentConversationPage), findsOneWidget);
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
    expect(find.byType(WebPublicEntryScaffold), findsNothing);

    await tester.pumpAndSettle();

    expect(find.byType(WebPublicEntryScaffold), findsOneWidget);
    expect(await store.readManagedVaultBaseUrl(), isNull);
    expect(
      await store.resolveManagedVaultBaseUrl(),
      'https://vault.secondloop.example',
    );
  });

  testWidgets(
      'web gate clears stale managed vault direct URL and uses runtime proxy URL',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      scopeKey: 'web-native:uid-1',
      managedVaultDefaultBaseUrl: 'https://secondloop.app/api/app/vault-proxy',
    );
    await store.writeManagedVaultBaseUrl(
      'https://service-vault.secondloop.app',
    );

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(
          initialUid: 'uid-1',
          initialEmail: 'user@example.com',
          initialEmailVerified: true,
        ),
        service:
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        managedVaultBaseUrl: 'https://secondloop.app/api/app/vault-proxy',
      ),
    );
    await tester.pumpAndSettle();

    expect(await store.readManagedVaultBaseUrl(), isNull);
    expect(
      await store.resolveManagedVaultBaseUrl(),
      'https://secondloop.app/api/app/vault-proxy',
    );
  });

  testWidgets('web gate times out hung sync-default priming', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final hungPrimer = Completer<void>();

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeCloudAuthController(),
        service: _FakeWebAppService(subscription: WebSubscriptionState.unknown),
        syncDefaultsPrimer: (_) => hungPrimer.future,
        syncDefaultsPrimingTimeout: const Duration(milliseconds: 10),
      ),
    );

    expect(find.byType(WebPublicEntryScaffold), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.byType(WebPublicEntryScaffold), findsOneWidget);
  });

  testWidgets('stale sync-default priming completion does not unlock new gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final firstPrimer = Completer<void>();
    final secondPrimer = Completer<void>();
    final controller = _FakeCloudAuthController();
    final service =
        _FakeWebAppService(subscription: WebSubscriptionState.unknown);
    var primerCalls = 0;

    await tester.pumpWidget(
      _buildApp(
        controller: controller,
        service: service,
        injectTestBackend: false,
        syncDefaultsPrimer: (_) {
          primerCalls += 1;
          return primerCalls == 1 ? firstPrimer.future : secondPrimer.future;
        },
        syncDefaultsPrimingTimeout: const Duration(days: 1),
      ),
    );
    await tester.pump();

    expect(find.byType(WebPublicEntryScaffold), findsNothing);
    await tester.pump();
    controller.setSession(
      uid: 'uid-2',
      email: 'user@example.com',
      emailVerified: true,
    );
    await tester.pump();

    firstPrimer.complete();
    await tester.pump();

    expect(find.byType(WebPublicEntryScaffold), findsNothing);

    secondPrimer.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPanel), findsOneWidget);
  });
}
