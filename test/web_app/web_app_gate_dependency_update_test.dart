import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/features/settings/cloud_account_panel.dart';
import 'package:secondloop/web_app/web_app_gate.dart';

import '../test_i18n.dart';
import '../test_backend.dart';

void main() {
  testWidgets('WebAppGate rebinds injected auth controller and service',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _buildApp(
        controller: _FakeObservableCloudAuthController(uid: null),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.unknown,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CloudAccountPanel), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);

    await tester.pumpWidget(
      _buildApp(
        controller: _FakeObservableCloudAuthController(uid: 'uid-2'),
        service: _FakeWebAppService(
          subscription: WebSubscriptionState.entitled,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(CloudAccountPanel), findsNothing);
  });
}

Widget _buildApp({
  required ObservableCloudAuthController controller,
  required WebAppService service,
}) {
  return wrapWithI18n(
    MaterialApp(
      home: WebAppGate(
        authController: controller,
        service: service,
        defaultBackendBuilder: () => _FakeUnlockedWebBackend(),
      ),
    ),
  );
}

final class _FakeUnlockedWebBackend extends TestAppBackend {
  @override
  Future<bool> isMasterPasswordSet() async => false;
}

final class _FakeObservableCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController {
  _FakeObservableCloudAuthController({required this.uid});

  @override
  final String? uid;

  @override
  String? get email => uid == null ? null : 'user@example.com';

  @override
  bool? get emailVerified => uid == null ? null : true;

  @override
  Future<String?> getIdToken() async => uid == null ? null : 'token';

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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

final class _FakeWebAppService extends WebAppService {
  _FakeWebAppService({required this.subscription});

  final WebSubscriptionState subscription;

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription(
          {required String idToken}) async =>
      WebSubscriptionSnapshot(
        state: subscription,
        canManageSubscription: subscription == WebSubscriptionState.entitled,
      );
}
