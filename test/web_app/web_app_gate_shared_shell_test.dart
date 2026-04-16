import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/features/settings/cloud_account_panel.dart';
import 'package:secondloop/features/settings/settings_page.dart';
import 'package:secondloop/web_app/web_app_gate.dart';
import 'package:secondloop/web_app/web_entry_intent.dart';

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

  final String? _uid;
  final String? _email;
  final bool? _emailVerified;

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
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

class _FakeWebAppService extends WebAppService {
  _FakeWebAppService({required this.subscription});

  final WebSubscriptionState subscription;

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription({
    required String idToken,
  }) async {
    return WebSubscriptionSnapshot(
      state: subscription,
      canManageSubscription: subscription == WebSubscriptionState.entitled,
    );
  }
}

Widget _buildApp({
  required ObservableCloudAuthController controller,
  required WebAppService service,
  CloudWebBackend? chatBackend,
  WebEntryIntent entryIntent = WebEntryIntent.open,
}) {
  return wrapWithI18n(
    MaterialApp(
      home: WebAppGate(
        authController: controller,
        service: service,
        chatBackend: chatBackend,
        defaultBackendBuilder: () => _FakeUnlockedWebBackend(),
        entryIntent: entryIntent,
      ),
    ),
  );
}

final class _FakeUnlockedWebBackend extends TestAppBackend {
  @override
  Future<bool> isMasterPasswordSet() async => false;
}

void main() {
  testWidgets('entitled users enter shared AppShell instead of WebAppShell',
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
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(CloudAccountPanel), findsNothing);
  });

  testWidgets('manage intent opens shared shell on settings tab',
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
            _FakeWebAppService(subscription: WebSubscriptionState.entitled),
        entryIntent: WebEntryIntent.manage,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Theme'), findsNothing);
    expect(find.byKey(const ValueKey('settings_theme_palette')), findsNothing);
  });
}
