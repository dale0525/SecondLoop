import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/settings/vault_usage_card.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';

import '../../test_i18n.dart';

void main() {
  testWidgets(
      'VaultUsageCard clears busy state after injected clients invalidate stale refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final firstAttachmentsResponse = Completer<http.Response>();
    final firstUsageHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'total_bytes_used': 1024,
          'attachments_bytes_used': 1024,
          'ops_bytes_used': 0,
          'other_bytes_used': 0,
          'limit_bytes': null,
        }),
        200,
      );
    });
    final firstAttachmentsHttpClient =
        MockClient((request) => firstAttachmentsResponse.future);

    final secondUsageHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'total_bytes_used': 2048,
          'attachments_bytes_used': 2048,
          'ops_bytes_used': 0,
          'other_bytes_used': 0,
          'limit_bytes': null,
        }),
        200,
      );
    });
    final secondAttachmentsHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'items': <Object?>[],
          'total_count': 0,
          'total_bytes_used': 0,
        }),
        200,
      );
    });

    Widget buildWidget({
      required VaultUsageClient usageClient,
      required VaultAttachmentsClient attachmentsClient,
    }) {
      return wrapWithI18n(
        AppBackendScope(
          backend: _FakeBackend(),
          child: CloudAuthScope(
            controller: _FakeCloudAuthController(),
            gatewayConfig: const CloudGatewayConfig(
              baseUrl: 'https://gateway.test',
              modelName: 'cloud',
            ),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: MaterialApp(
                home: Scaffold(
                  body: VaultUsageCard(
                    client: usageClient,
                    attachmentsClient: attachmentsClient,
                    configStore: SyncConfigStore(
                      managedVaultDefaultBaseUrl: 'https://vault.test',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      buildWidget(
        usageClient: VaultUsageClient(httpClient: firstUsageHttpClient),
        attachmentsClient:
            VaultAttachmentsClient(httpClient: firstAttachmentsHttpClient),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      buildWidget(
        usageClient: VaultUsageClient(httpClient: secondUsageHttpClient),
        attachmentsClient:
            VaultAttachmentsClient(httpClient: secondAttachmentsHttpClient),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('vault_usage_refresh')))
          .onPressed,
      isNotNull,
    );
  });
}

final class _FakeBackend implements AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
