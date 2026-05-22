import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud/vault_attachments_client.dart';
import '../attachments/non_image_attachment_view.dart'
    show fileExtensionForSystemOpenMimeType;

Future<bool> openVaultAttachmentContent({
  required VaultAttachmentUsageItem item,
  required VaultAttachmentContent content,
}) async {
  final dir = await getTemporaryDirectory();
  final attachmentDir = Directory(
    '${dir.path}${Platform.pathSeparator}secondloop-vault-previews'
    '${Platform.pathSeparator}${_safePathSegment(item.attachmentId)}',
  );
  await attachmentDir.create(recursive: true);
  final file = File(
    '${attachmentDir.path}${Platform.pathSeparator}'
    '${_downloadFilename(item, content.mimeType)}',
  );
  await file.writeAsBytes(content.bytes, flush: true);
  return launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
}

String _downloadFilename(VaultAttachmentUsageItem item, String mimeType) {
  final displayName = item.displayName?.trim() ?? '';
  if (displayName.isNotEmpty) return _safeFilename(displayName);
  final stem = item.primarySha256.trim().isEmpty
      ? item.attachmentId.trim()
      : item.primarySha256.trim();
  final normalizedStem = stem.isEmpty ? 'attachment' : stem;
  return '${_safeFilename(normalizedStem)}'
      '${fileExtensionForSystemOpenMimeType(mimeType)}';
}

String _safePathSegment(String value) {
  final normalized = _safeFilename(value.trim());
  return normalized.isEmpty ? 'attachment' : normalized;
}

String _safeFilename(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  final withoutDotPrefix = normalized.replaceFirst(RegExp(r'^\.+'), '');
  return withoutDotPrefix.isEmpty ? 'attachment' : withoutDotPrefix;
}
