import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/features/settings/cloud_usage_card.dart';
import 'package:secondloop/ui/sl_surface.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Cloud usage card uses SlSurface', (tester) async {
    final controller = _FakeCloudAuthController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: controller,
            gatewayConfig:
                const CloudGatewayConfig(baseUrl: '', modelName: 'cloud'),
            child: const Scaffold(body: CloudUsageCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CloudUsageCard), findsOneWidget);
    expect(find.byType(SlSurface), findsOneWidget);
  });
}

final class _FakeCloudAuthController implements CloudAuthController {
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
