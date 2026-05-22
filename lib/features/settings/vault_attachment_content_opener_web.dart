// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import '../../core/cloud/vault_attachments_client.dart';
import '../attachments/non_image_attachment_view.dart'
    show fileExtensionForSystemOpenMimeType;

Future<bool> openVaultAttachmentContent({
  required VaultAttachmentUsageItem item,
  required VaultAttachmentContent content,
}) async {
  final blob = html.Blob(<Object>[content.bytes], content.mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = _downloadFilename(item, content.mimeType)
    ..target = '_blank'
    ..rel = 'noopener';
  anchor.click();
  Future<void>.microtask(() => html.Url.revokeObjectUrl(url));
  return true;
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

String _safeFilename(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  final withoutDotPrefix = normalized.replaceFirst(RegExp(r'^\.+'), '');
  return withoutDotPrefix.isEmpty ? 'attachment' : withoutDotPrefix;
}
