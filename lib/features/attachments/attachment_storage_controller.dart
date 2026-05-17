import 'package:flutter/foundation.dart';

import '../../core/cloud/vault_attachments_client.dart';
import 'attachment_preview_descriptor.dart';

abstract interface class AttachmentLocalCacheMetadataStore {
  Future<void> recordPreviewAccess({
    required String attachmentId,
    required String url,
  });

  Future<void> clearAttachmentCacheMetadata(VaultAttachmentUsageItem item);
}

final class InMemoryAttachmentLocalCacheMetadataStore
    implements AttachmentLocalCacheMetadataStore {
  final Map<String, String> _lastPreviewUrlByAttachmentId = <String, String>{};
  final Set<String> _clearedAttachmentIds = <String>{};

  @override
  Future<void> recordPreviewAccess({
    required String attachmentId,
    required String url,
  }) async {
    _lastPreviewUrlByAttachmentId[attachmentId] = url;
    _clearedAttachmentIds.remove(attachmentId);
  }

  @override
  Future<void> clearAttachmentCacheMetadata(
    VaultAttachmentUsageItem item,
  ) async {
    _lastPreviewUrlByAttachmentId.remove(item.attachmentId);
    _clearedAttachmentIds.add(item.attachmentId);
  }
}

final class AttachmentStorageController extends ChangeNotifier {
  AttachmentStorageController({
    required VaultAttachmentsClient client,
    required AttachmentLocalCacheMetadataStore localCacheMetadataStore,
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  })  : _client = client,
        _localCacheMetadataStore = localCacheMetadataStore,
        _managedVaultBaseUrl = managedVaultBaseUrl,
        _vaultId = vaultId,
        _idToken = idToken;

  final VaultAttachmentsClient _client;
  final AttachmentLocalCacheMetadataStore _localCacheMetadataStore;
  final String _managedVaultBaseUrl;
  final String _vaultId;
  final String _idToken;

  List<VaultAttachmentUsageItem> _items = const <VaultAttachmentUsageItem>[];

  List<VaultAttachmentUsageItem> get items => _items;

  Future<void> refresh({int limit = 200}) async {
    final list = await _client.fetchVaultAttachmentUsageList(
      managedVaultBaseUrl: _managedVaultBaseUrl,
      vaultId: _vaultId,
      idToken: _idToken,
      limit: limit,
    );
    _items = List<VaultAttachmentUsageItem>.unmodifiable(
      List<VaultAttachmentUsageItem>.from(list.items)
        ..sort(_compareBySizeDescending),
    );
    notifyListeners();
  }

  Future<AttachmentPreviewDescriptor> previewAttachment(
    VaultAttachmentUsageItem item,
  ) async {
    final preview = await _client.fetchAttachmentPreview(
      managedVaultBaseUrl: _managedVaultBaseUrl,
      vaultId: _vaultId,
      idToken: _idToken,
      attachmentId: item.attachmentId,
    );
    await _localCacheMetadataStore.recordPreviewAccess(
      attachmentId: item.attachmentId,
      url: preview.url,
    );
    return AttachmentPreviewDescriptor(
      kind: preview.kind,
      url: preview.url,
      thumbnailUrl: preview.thumbnailUrl,
    );
  }

  Future<VaultAttachmentDeleteImpact> deleteAttachment(
    VaultAttachmentUsageItem item,
  ) async {
    final impact = await _client.fetchDeleteImpact(
      managedVaultBaseUrl: _managedVaultBaseUrl,
      vaultId: _vaultId,
      idToken: _idToken,
      attachmentId: item.attachmentId,
    );
    await _client.deleteVaultAttachment(
      managedVaultBaseUrl: _managedVaultBaseUrl,
      vaultId: _vaultId,
      idToken: _idToken,
      attachmentId: item.attachmentId,
    );
    await _localCacheMetadataStore.clearAttachmentCacheMetadata(item);
    return impact;
  }

  Future<void> clearLocalCache(VaultAttachmentUsageItem item) {
    return _localCacheMetadataStore.clearAttachmentCacheMetadata(item);
  }
}

int _compareBySizeDescending(
  VaultAttachmentUsageItem a,
  VaultAttachmentUsageItem b,
) {
  final byBytes = b.byteLen - a.byteLen;
  if (byBytes != 0) return byBytes;
  final byUploaded = (b.uploadedAtMs ?? 0) - (a.uploadedAtMs ?? 0);
  if (byUploaded != 0) return byUploaded;
  return a.attachmentId.compareTo(b.attachmentId);
}
