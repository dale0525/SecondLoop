import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/settings/vault_usage_card.dart';

import 'test_i18n.dart';

Future<void> _pumpUi(WidgetTester tester, {int cycles = 16}) async {
  for (var i = 0; i < cycles; i += 1) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

void main() {
  testWidgets(
      'VaultUsageCard opens authorized preview content without launching auth URL',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final requestedUrls = <String>[];
    final opened =
        <({VaultAttachmentUsageItem item, VaultAttachmentContent content})>[];

    final httpClient = MockClient((request) async {
      requestedUrls.add(request.url.toString());
      final url = request.url.toString();
      if (url == 'https://vault.test/v1/vaults/uid_1/usage') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'total_bytes_used': 3,
            'attachments_bytes_used': 3,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': null,
          }),
          200,
        );
      }
      if (url == 'https://vault.test/v1/vaults/uid_1/attachments?limit=200') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'items': [
              {
                'id': 'att-1',
                'sha256': 'sha-1',
                'display_name': 'source.pdf',
                'mime_type': 'application/pdf',
                'byte_len': 3,
                'created_at_ms': 1000,
                'uploaded_at_ms': 2000,
              },
            ],
            'total_count': 1,
            'total_bytes_used': 3,
          }),
          200,
        );
      }
      if (url ==
          'https://vault.test/v1/vaults/uid_1/attachments/att-1/preview') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'kind': 'pdf',
            'url': '/v1/vaults/uid_1/attachments/att-1/content',
          }),
          200,
        );
      }
      if (url ==
          'https://vault.test/v1/vaults/uid_1/attachments/att-1/content') {
        expect(request.headers['authorization'], 'Bearer token_1');
        return http.Response.bytes(
          <int>[0x25, 0x50, 0x44, 0x46],
          200,
          headers: const <String, String>{
            'content-type': 'application/pdf',
          },
        );
      }
      throw StateError('unexpected url: $url');
    });

    await tester.pumpWidget(
      wrapWithI18n(
        CloudAuthScope(
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
                  client: VaultUsageClient(httpClient: httpClient),
                  attachmentsClient:
                      VaultAttachmentsClient(httpClient: httpClient),
                  configStore: SyncConfigStore(
                    managedVaultDefaultBaseUrl: 'https://vault.test',
                  ),
                  attachmentContentOpener: ({
                    required item,
                    required content,
                  }) async {
                    opened.add((item: item, content: content));
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _pumpUi(tester);
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('vault_usage_attachment_sha-1')));
    await _pumpUi(tester);

    expect(
      requestedUrls,
      contains(
        'https://vault.test/v1/vaults/uid_1/attachments/att-1/content',
      ),
    );
    expect(opened, hasLength(1));
    expect(opened.single.item.displayName, 'source.pdf');
    expect(opened.single.content.mimeType, 'application/pdf');
    expect(opened.single.content.bytes, <int>[0x25, 0x50, 0x44, 0x46]);
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
