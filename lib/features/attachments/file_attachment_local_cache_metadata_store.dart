import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/cloud/vault_attachments_client.dart';
import 'attachment_storage_controller.dart';

typedef AppSupportDirectoryProvider = Future<Directory> Function();

final class FileAttachmentLocalCacheMetadataStore
    implements AttachmentLocalCacheMetadataStore {
  FileAttachmentLocalCacheMetadataStore({
    AppSupportDirectoryProvider? appSupportDirectoryProvider,
  }) : _appSupportDirectoryProvider =
            appSupportDirectoryProvider ?? getApplicationSupportDirectory;

  final AppSupportDirectoryProvider _appSupportDirectoryProvider;

  @override
  Future<void> recordPreviewAccess({
    required String attachmentId,
    required String url,
  }) async {}

  @override
  Future<void> clearAttachmentCacheMetadata(
    VaultAttachmentUsageItem item,
  ) async {
    final shaCandidates = <String>{
      item.sha256.trim(),
      item.primarySha256.trim(),
    }..removeWhere((value) => value.isEmpty);
    if (shaCandidates.isEmpty) return;

    final appSupportDir = await _appSupportDirectoryProvider();
    final attachmentsDir = Directory('${appSupportDir.path}/attachments');
    for (final sha256 in shaCandidates) {
      await _deleteIfExists(File('${attachmentsDir.path}/$sha256.bin'));
      await _deleteIfExists(
        Directory('${attachmentsDir.path}/variants/$sha256'),
      );
    }
  }

  Future<void> _deleteIfExists(FileSystemEntity entity) async {
    if (!await entity.exists()) return;
    await entity.delete(recursive: true);
  }
}
