import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';

void main() {
  test('VaultAttachmentsClient parses grouped attachments list', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://vault.test/v1/vaults/vault-1/attachments?limit=200',
      );
      return http.Response(
        jsonEncode({
          'items': [
            {
              'sha256': 'leaf-sha',
              'root_sha256': 'root-sha',
              'group_type': 'video',
              'leaf_count': 3,
              'mime_type': 'video/mp4',
              'byte_len': 4096,
              'created_at_ms': 1000,
              'uploaded_at_ms': 2000,
            }
          ],
          'total_count': 1,
          'total_bytes_used': 4096,
        }),
        200,
      );
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    final list = await attachmentsClient.fetchVaultAttachmentUsageList(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );

    expect(list.totalCount, 1);
    expect(list.totalBytesUsed, 4096);
    expect(list.items.single.primarySha256, 'root-sha');
    expect(list.items.single.isGroupedVideo, true);
  });

  test('VaultAttachmentsClient deletes attachment with delete request',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(
        request.url.toString(),
        'https://vault.test/v1/vaults/vault-1/attachments/sha-1',
      );
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response('{}', 204);
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    await attachmentsClient.deleteVaultAttachment(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
      attachmentSha256: 'sha-1',
    );
  });
}
