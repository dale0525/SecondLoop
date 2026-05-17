import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/features/attachments/attachment_storage_controller.dart';
import 'package:secondloop/features/attachments/file_attachment_local_cache_metadata_store.dart';

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
    final cache = _FakeLocalCacheMetadataStore();
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
      localCacheMetadataStore: cache,
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
    expect(cache.clearedAttachmentIds, ['att-1:sha-1']);
  });

  test('delete removes cached attachment bytes and variants after cloud delete',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('attachment_delete_test_');
    addTearDown(() => dir.delete(recursive: true));
    final attachmentsDir = Directory('${dir.path}/attachments');
    final variantsDir = Directory('${attachmentsDir.path}/variants/sha-1');
    await variantsDir.create(recursive: true);
    final primary = File('${attachmentsDir.path}/sha-1.bin');
    final variant = File('${variantsDir.path}/preview.webp');
    await primary.writeAsString('primary');
    await variant.writeAsString('variant');

    final controller = AttachmentStorageController(
      client: VaultAttachmentsClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/delete-impact')) {
            return http.Response(
              jsonEncode({
                'requires_confirmation': false,
                'linked_entities': <Object?>[],
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      ),
      localCacheMetadataStore: FileAttachmentLocalCacheMetadataStore(
        appSupportDirectoryProvider: () async => dir,
      ),
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );

    await controller.deleteAttachment(
      const VaultAttachmentUsageItem(
        id: 'att-1',
        sha256: 'sha-1',
        mimeType: 'application/pdf',
        byteLen: 128,
        createdAtMs: 1000,
        uploadedAtMs: 2000,
      ),
    );

    expect(await primary.exists(), false);
    expect(await variantsDir.exists(), false);
  });

  test('local cache cleanup deletes local metadata only and avoids cloud calls',
      () async {
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

    expect(cache.clearedAttachmentIds, ['att-1:sha-1']);
    expect(cloudCalls, 0);
  });

  test('file cache cleanup removes primary attachment bytes and variants only',
      () async {
    final dir = await Directory.systemTemp.createTemp('attachment_cache_test_');
    addTearDown(() => dir.delete(recursive: true));
    final attachmentsDir = Directory('${dir.path}/attachments');
    final variantsDir = Directory('${attachmentsDir.path}/variants/sha-1');
    await variantsDir.create(recursive: true);
    final primary = File('${attachmentsDir.path}/sha-1.bin');
    final variant = File('${variantsDir.path}/preview.webp');
    final unrelated = File('${attachmentsDir.path}/sha-2.bin');
    await primary.writeAsString('primary');
    await variant.writeAsString('variant');
    await unrelated.writeAsString('unrelated');

    final store = FileAttachmentLocalCacheMetadataStore(
      appSupportDirectoryProvider: () async => dir,
    );

    await store.clearAttachmentCacheMetadata(
      const VaultAttachmentUsageItem(
        id: 'att-1',
        sha256: 'sha-1',
        mimeType: 'application/pdf',
        byteLen: 128,
        createdAtMs: 1000,
        uploadedAtMs: 2000,
      ),
    );

    expect(await primary.exists(), false);
    expect(await variantsDir.exists(), false);
    expect(await unrelated.exists(), true);
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
  Future<void> clearAttachmentCacheMetadata(
    VaultAttachmentUsageItem item,
  ) async {
    clearedAttachmentIds.add('${item.attachmentId}:${item.primarySha256}');
  }
}
