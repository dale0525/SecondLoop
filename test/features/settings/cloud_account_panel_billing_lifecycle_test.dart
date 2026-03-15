import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/subscription/creem_billing_client.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/settings/cloud_account_panel.dart';

import '../../test_i18n.dart';

void main() {
  testWidgets('CloudAccountPanel reuses and disposes owned billing client',
      (tester) async {
    var createdCount = 0;
    var disposedCount = 0;
    final controller = _FakeCloudAuthController();
    final subscriptions = _FakeSubscriptionStatusController(
      SubscriptionStatus.notEntitled,
    );

    Widget buildWidget() {
      return wrapWithI18n(
        MaterialApp(
          home: SubscriptionScope(
            controller: subscriptions,
            child: CloudAuthScope(
              controller: controller,
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.test',
                modelName: 'cloud',
              ),
              child: Scaffold(
                body: ListView(
                  children: [
                    CloudAccountPanel(
                      billingClientFactory: ({
                        required idTokenGetter,
                        required cloudGatewayBaseUrl,
                      }) {
                        createdCount += 1;
                        return _FakeDisposableBillingClient(
                          onDispose: () => disposedCount += 1,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWidget());
    await tester.pumpAndSettle();

    final subscribeButton = find.byKey(const ValueKey('cloud_subscribe'));
    await tester.dragUntilVisible(
      subscribeButton,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(subscribeButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      subscribeButton,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(subscribeButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(createdCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(disposedCount, 1);
  });
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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _FakeDisposableBillingClient implements DisposableBillingClient {
  _FakeDisposableBillingClient({required this.onDispose});

  final VoidCallback onDispose;

  @override
  void dispose() => onDispose();

  @override
  Future<void> openCheckout() async {}

  @override
  Future<void> openPortal() async {}
}
