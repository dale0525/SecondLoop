import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/web_app/web_app_gate.dart';

import '../test_i18n.dart';

void main() {
  testWidgets('WebAppGate rejects non-listenable auth controllers explicitly',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: WebAppGate(
            authController: _NonListenableCloudAuthController(),
            service: _FakeWebAppService(),
          ),
        ),
      ),
    );

    final error = tester.takeException();
    expect(error, isA<StateError>());
    expect(
      error.toString(),
      contains('Listenable CloudAuthController'),
    );
  });
}

final class _NonListenableCloudAuthController
    implements CloudAuthController, CloudPasswordRecoveryController {
  @override
  String? get uid => null;

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => null;

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

final class _FakeWebAppService extends WebAppService {
  @override
  Future<WebSubscriptionSnapshot> fetchSubscription(
          {required String idToken}) async =>
      const WebSubscriptionSnapshot(
        state: WebSubscriptionState.unknown,
        canManageSubscription: null,
      );
}
