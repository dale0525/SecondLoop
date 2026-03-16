import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/features/settings/cloud_usage_card.dart';

import '../../test_i18n.dart';

void main() {
  testWidgets(
      'CloudUsageCard clears busy state after injected client invalidates stale refresh',
      (tester) async {
    final firstResponse = Completer<http.Response>();
    final firstHttpClient = MockClient((request) => firstResponse.future);
    final secondHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'ask_ai_usage_percent': 22,
          'embeddings_usage_percent': 2,
          'reset_at_ms': 456,
        }),
        200,
      );
    });

    Widget buildWidget(CloudUsageClient client) {
      return wrapWithI18n(
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
      );
    }

    await tester.pumpWidget(
      buildWidget(CloudUsageClient(httpClient: firstHttpClient)),
    );
    await tester.pump();

    await tester.pumpWidget(
      buildWidget(CloudUsageClient(httpClient: secondHttpClient)),
    );
    await tester.pumpAndSettle();

    expect(find.text('22%'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('cloud_usage_refresh')))
          .onPressed,
      isNotNull,
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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
