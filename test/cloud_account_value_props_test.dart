import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Cloud account page shows cloud benefits before sign-in',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(home: CloudAccountPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud_account_value_props')),
        findsOneWidget);
  });

  testWidgets('Cloud account page shows subscription benefits before purchase',
      (tester) async {
    final auth = _FakeCloudAuthController();
    final subscriptions =
        _FakeSubscriptionStatusController(SubscriptionStatus.notEntitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SubscriptionScope(
            controller: subscriptions,
            child: CloudAuthScope(
              controller: auth,
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.test',
                modelName: 'cloud',
              ),
              child: const CloudAccountPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud_subscription_value_props')),
        findsOneWidget);
  });
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'test@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token_1';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
