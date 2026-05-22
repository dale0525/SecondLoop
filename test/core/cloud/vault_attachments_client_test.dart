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

  test('VaultAttachmentsClient parses cloud attachment inventory fields',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 'att-1',
              'sha256': 'sha-1',
              'display_name': 'receipt.pdf',
              'mime_type': 'application/pdf',
              'byte_len': 102400,
              'created_at_ms': 1000,
              'uploaded_at_ms': 2000,
              'linked_entities': [
                {'kind': 'note', 'id': 'note-1', 'title': 'Trip'}
              ],
              'preview': {
                'kind': 'pdf',
                'url': 'https://signed.test/preview',
                'thumbnail_url': 'https://signed.test/thumb',
              },
              'processing_status': 'ready',
              'can_delete': true,
            }
          ],
          'total_count': 1,
          'total_bytes_used': 102400,
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

    final item = list.items.single;
    expect(item.id, 'att-1');
    expect(item.displayName, 'receipt.pdf');
    expect(item.linkedEntities.single.kind, 'note');
    expect(item.linkedEntities.single.id, 'note-1');
    expect(item.linkedEntities.single.title, 'Trip');
    expect(item.preview?.kind, 'pdf');
    expect(item.preview?.url, 'https://signed.test/preview');
    expect(item.preview?.thumbnailUrl, 'https://signed.test/thumb');
    expect(item.processingStatus, 'ready');
    expect(item.canDelete, true);
  });

  test('VaultAttachmentsClient accepts filename as attachment display name',
      () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 'att-1',
              'sha256': 'sha-1',
              'filename': 'original-recording.m4a',
              'mime_type': 'audio/mp4',
              'byte_len': 2048,
            }
          ],
          'total_count': 1,
          'total_bytes_used': 2048,
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

    expect(list.items.single.displayName, 'original-recording.m4a');
  });

  test('VaultAttachmentsClient fetches attachment preview', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://vault.test/v1/vaults/vault-1/attachments/att-1/preview',
      );
      return http.Response(
        jsonEncode({
          'kind': 'image',
          'url': 'https://signed.test/preview',
          'thumbnail_url': 'https://signed.test/thumb',
        }),
        200,
      );
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    final preview = await attachmentsClient.fetchAttachmentPreview(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
      attachmentId: 'att-1',
    );

    expect(preview.kind, 'image');
    expect(preview.url, 'https://signed.test/preview');
    expect(preview.thumbnailUrl, 'https://signed.test/thumb');
  });

  test('VaultAttachmentsClient resolves relative preview urls', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'kind': 'download',
          'url': '/v1/vaults/vault-1/attachments/att-1/content',
        }),
        200,
      );
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    final preview = await attachmentsClient.fetchAttachmentPreview(
      managedVaultBaseUrl: 'https://vault.test/base/',
      vaultId: 'vault-1',
      idToken: 'token-1',
      attachmentId: 'att-1',
    );

    expect(
      preview.url,
      'https://vault.test/v1/vaults/vault-1/attachments/att-1/content',
    );
  });

  test('VaultAttachmentsClient falls back when preview route is missing',
      () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://vault.test/v1/vaults/vault-1/attachments/att-1/preview',
      );
      return http.Response(jsonEncode({'error': 'not_found'}), 404);
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    final preview = await attachmentsClient.fetchAttachmentPreview(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
      attachmentId: 'att-1',
    );

    expect(preview.kind, 'download');
    expect(
      preview.url,
      'https://vault.test/v1/vaults/vault-1/attachments/att-1',
    );
  });

  test('VaultAttachmentsClient fetches authorized attachment content',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://vault.test/v1/vaults/vault-1/attachments/att-1/content',
      );
      expect(request.headers['authorization'], 'Bearer token-1');
      expect(request.headers['accept'], '*/*');
      return http.Response.bytes(
        <int>[1, 2, 3],
        200,
        headers: const <String, String>{'content-type': 'application/pdf'},
      );
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    final content = await attachmentsClient.fetchAttachmentContent(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
      attachmentId: 'att-1',
      contentUrl: '/v1/vaults/vault-1/attachments/att-1/content',
    );

    expect(content.mimeType, 'application/pdf');
    expect(content.bytes, <int>[1, 2, 3]);
  });

  test('VaultAttachmentsClient falls back to direct attachment content route',
      () async {
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      if (request.url.path.endsWith('/content')) {
        return http.Response(jsonEncode({'error': 'not_found'}), 404);
      }
      return http.Response.bytes(
        <int>[4, 5],
        200,
        headers: const <String, String>{'content-type': 'image/png'},
      );
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    final content = await attachmentsClient.fetchAttachmentContent(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
      attachmentId: 'sha-1',
      contentUrl: '/v1/vaults/vault-1/attachments/sha-1/content',
    );

    expect(urls, <String>[
      'https://vault.test/v1/vaults/vault-1/attachments/sha-1/content',
      'https://vault.test/v1/vaults/vault-1/attachments/sha-1',
    ]);
    expect(content.mimeType, 'image/png');
    expect(content.bytes, <int>[4, 5]);
  });

  test('VaultAttachmentsClient fetches delete impact', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://vault.test/v1/vaults/vault-1/attachments/att-1/delete-impact',
      );
      return http.Response(
        jsonEncode({
          'requires_confirmation': true,
          'linked_entities': [
            {'kind': 'note', 'id': 'note-1', 'title': 'Trip'}
          ],
        }),
        200,
      );
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    final impact = await attachmentsClient.fetchDeleteImpact(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
      attachmentId: 'att-1',
    );

    expect(impact.requiresConfirmation, true);
    expect(impact.linkedEntities.single.id, 'note-1');
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

  test('VaultAttachmentsClient deletes attachment by id', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(
        request.url.toString(),
        'https://vault.test/v1/vaults/vault-1/attachments/att-1',
      );
      return http.Response('', 204);
    });

    final attachmentsClient = VaultAttachmentsClient(httpClient: client);
    await attachmentsClient.deleteVaultAttachment(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
      attachmentId: 'att-1',
    );
  });
}
