import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/features/attachments/attachment_storage_controller.dart';

void main() {
  test('refresh sorts cloud attachments by size descending', () async {
    final controller = AttachmentStorageController(
      client: VaultAttachmentsClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({
              'items': [
                _attachmentJson(id: 'att-small', sha256: 'sha-small', size: 64),
                _attachmentJson(
                    id: 'att-large', sha256: 'sha-large', size: 512),
              ],
              'total_count': 2,
              'total_bytes_used': 576,
            }),
            200,
          );
        }),
      ),
      localCacheMetadataStore: _FakeLocalCacheMetadataStore(),
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );

    await controller.refresh();

    expect(controller.items.map((item) => item.id), ['att-large', 'att-small']);
  });

  test('preview returns signed URL descriptor and records local cache access',
      () async {
    final cache = _FakeLocalCacheMetadataStore();
    final controller = AttachmentStorageController(
      client: VaultAttachmentsClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://vault.test/v1/vaults/vault-1/attachments/att-1/preview',
          );
          return http.Response(
            jsonEncode({
              'kind': 'pdf',
              'url': 'https://signed.test/preview',
              'thumbnail_url': 'https://signed.test/thumb',
            }),
            200,
          );
        }),
      ),
      localCacheMetadataStore: cache,
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );

    final descriptor = await controller.previewAttachment(
      const VaultAttachmentUsageItem(
        id: 'att-1',
        sha256: 'sha-1',
        mimeType: 'application/pdf',
        byteLen: 128,
        createdAtMs: 1000,
        uploadedAtMs: 2000,
      ),
    );

    expect(descriptor.kind, 'pdf');
    expect(descriptor.url, 'https://signed.test/preview');
    expect(descriptor.thumbnailUrl, 'https://signed.test/thumb');
    expect(cache.previewAccesses, ['att-1:https://signed.test/preview']);
  });

  test('delete loads impact before invoking cloud delete', () async {
    final calls = <String>[];
    final controller = AttachmentStorageController(
      client: VaultAttachmentsClient(
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/delete-impact')) {
            return http.Response(
              jsonEncode({
                'requires_confirmation': true,
                'linked_entities': [
                  {'kind': 'note', 'id': 'note-1', 'title': 'Trip'}
                ],
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      ),
      localCacheMetadataStore: _FakeLocalCacheMetadataStore(),
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );

    final impact = await controller.deleteAttachment(
      const VaultAttachmentUsageItem(
        id: 'att-1',
        sha256: 'sha-1',
        mimeType: 'application/pdf',
        byteLen: 128,
        createdAtMs: 1000,
        uploadedAtMs: 2000,
      ),
    );

    expect(impact.requiresConfirmation, true);
    expect(impact.linkedEntities.single.title, 'Trip');
    expect(calls, [
      'GET /v1/vaults/vault-1/attachments/att-1/delete-impact',
      'DELETE /v1/vaults/vault-1/attachments/att-1',
    ]);
  });

  test('local cache cleanup deletes cache metadata only', () async {
    var cloudCalls = 0;
    final cache = _FakeLocalCacheMetadataStore();
    final controller = AttachmentStorageController(
      client: VaultAttachmentsClient(
        httpClient: MockClient((request) async {
          cloudCalls += 1;
          return http.Response('', 500);
        }),
      ),
      localCacheMetadataStore: cache,
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );

    await controller.clearLocalCache(
      const VaultAttachmentUsageItem(
        id: 'att-1',
        sha256: 'sha-1',
        mimeType: 'application/pdf',
        byteLen: 128,
        createdAtMs: 1000,
        uploadedAtMs: 2000,
      ),
    );

    expect(cache.clearedAttachmentIds, ['att-1']);
    expect(cloudCalls, 0);
  });
}

Map<String, Object?> _attachmentJson({
  required String id,
  required String sha256,
  required int size,
}) =>
    {
      'id': id,
      'sha256': sha256,
      'display_name': '$id.pdf',
      'mime_type': 'application/pdf',
      'byte_len': size,
      'created_at_ms': 1000,
      'uploaded_at_ms': 2000,
      'processing_status': 'ready',
      'can_delete': true,
    };

final class _FakeLocalCacheMetadataStore
    implements AttachmentLocalCacheMetadataStore {
  final previewAccesses = <String>[];
  final clearedAttachmentIds = <String>[];

  @override
  Future<void> recordPreviewAccess({
    required String attachmentId,
    required String url,
  }) async {
    previewAccesses.add('$attachmentId:$url');
  }

  @override
  Future<void> clearAttachmentCacheMetadata(String attachmentId) async {
    clearedAttachmentIds.add(attachmentId);
  }
}
