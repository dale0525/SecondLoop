import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';

void main() {
  test('VaultUsageClient parses managed vault usage payload', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
          request.url.toString(), 'https://vault.test/v1/vaults/vault-1/usage');
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response(
        jsonEncode({
          'total_bytes_used': 100,
          'attachments_bytes_used': 70,
          'ops_bytes_used': 20,
          'other_bytes_used': 10,
          'limit_bytes': 2048,
        }),
        200,
      );
    });

    final usageClient = VaultUsageClient(httpClient: client);
    final summary = await usageClient.fetchVaultUsageSummary(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );

    expect(summary.totalBytesUsed, 100);
    expect(summary.attachmentsBytesUsed, 70);
    expect(summary.opsBytesUsed, 20);
    expect(summary.otherBytesUsed, 10);
    expect(summary.limitBytes, 2048);
  });
}
