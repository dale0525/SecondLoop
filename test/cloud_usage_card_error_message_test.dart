import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/features/settings/cloud_usage_card.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  testWidgets('Cloud usage shows localized payment-required error',
      (tester) async {
    final client = CloudUsageClient(
      httpClient: MockClient(
        (_) async => http.Response('{"error":"payment_required"}', 402),
      ),
    );
    addTearDown(client.dispose);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: _FakeCloudAuthController(),
            gatewayConfig: const CloudGatewayConfig(
              baseUrl: 'https://gateway.test',
              modelName: 'cloud',
            ),
            child: Scaffold(body: CloudUsageCard(client: client)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('payment_required'), findsNothing);
    expect(
      find.text('Failed to load: Subscription required to view cloud usage.'),
      findsOneWidget,
    );
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
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
