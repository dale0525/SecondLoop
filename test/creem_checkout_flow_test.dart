import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/subscription/cloud_subscription_controller.dart';
import 'package:secondloop/core/subscription/creem_billing_client.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'Cloud account subscription does not show portal button when not entitled',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final billing = _FakeBillingClient();
      final subscriptions =
          _FakeSubscriptionStatusController(SubscriptionStatus.notEntitled);
      final auth = _FakeCloudAuthController();

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
                child: CloudAccountPage(billingClient: billing),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('cloud_subscribe')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cloud_subscribe')));
      await tester.pumpAndSettle();
      expect(billing.openCheckoutCalls, 1);

      expect(find.byKey(const ValueKey('cloud_manage_subscription')),
          findsNothing);
      expect(billing.openPortalCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Cloud account subscription shows portal button when entitled',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final billing = _FakeBillingClient();
      final subscriptions =
          _FakeSubscriptionStatusController(SubscriptionStatus.entitled);
      final auth = _FakeCloudAuthController();

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
                child: CloudAccountPage(billingClient: billing),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cloud_subscribe')), findsNothing);

      await tester.ensureVisible(
          find.byKey(const ValueKey('cloud_manage_subscription')));
      await tester.tap(find.byKey(const ValueKey('cloud_manage_subscription')));
      await tester.pumpAndSettle();
      expect(billing.openPortalCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'Cloud account subscription does not show portal button when customer id is missing',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final billing = _FakeBillingClient();
      final subscriptions = _FakeSubscriptionDetailsController(
        status: SubscriptionStatus.entitled,
        canManageSubscription: false,
      );
      final auth = _FakeCloudAuthController();

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
                child: CloudAccountPage(billingClient: billing),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cloud_subscribe')), findsNothing);
      expect(find.byKey(const ValueKey('cloud_manage_subscription')),
          findsNothing);
      expect(billing.openPortalCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'Cloud account subscription does not show portal button when gateway says portal unavailable',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    CloudSubscriptionController? subscriptions;
    try {
      final billing = _FakeBillingClient();
      final auth = _FakeCloudAuthController();

      subscriptions = CloudSubscriptionController(
        idTokenGetter: auth.getIdToken,
        cloudGatewayBaseUrl: 'https://gateway.test',
        httpClient: _FakeHttpClient(
          statusCode: 200,
          body: jsonEncode({
            'ok': true,
            'uid': 'uid_1',
            'entitlement_id': 'cloud_ai',
            'active': true,
            'expires_at_ms': null,
            'can_manage_subscription': false,
          }),
        ),
      );

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
                child: CloudAccountPage(billingClient: billing),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cloud_subscribe')), findsNothing);
      expect(find.byKey(const ValueKey('cloud_manage_subscription')),
          findsNothing);
      expect(billing.openPortalCalls, 0);
    } finally {
      subscriptions?.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;

  void setStatus(SubscriptionStatus next) {
    _status = next;
    notifyListeners();
  }
}

final class _FakeSubscriptionDetailsController extends ChangeNotifier
    implements SubscriptionDetailsController {
  _FakeSubscriptionDetailsController({
    required this.status,
    required this.canManageSubscription,
  });

  @override
  SubscriptionStatus status;

  @override
  bool? canManageSubscription;
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

final class _FakeBillingClient implements BillingClient {
  int openCheckoutCalls = 0;
  int openPortalCalls = 0;

  @override
  Future<void> openCheckout() async {
    openCheckoutCalls += 1;
  }

  @override
  Future<void> openPortal() async {
    openPortalCalls += 1;
  }
}

final class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(body)]),
      statusCode,
      request: request,
      headers: const <String, String>{
        'content-type': 'application/json',
      },
    );
  }
}
