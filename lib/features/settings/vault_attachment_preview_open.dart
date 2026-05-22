import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud/vault_attachments_client.dart';
import 'vault_attachment_content_opener.dart';

typedef VaultAttachmentExternalLauncher = Future<bool> Function(Uri uri);

Future<bool> openVaultAttachmentPreview({
  required VaultAttachmentsClient client,
  required VaultAttachmentUsageItem item,
  required String managedVaultBaseUrl,
  required String vaultId,
  required String idToken,
  required VaultAttachmentContentOpener contentOpener,
  VaultAttachmentExternalLauncher? externalLauncher,
}) async {
  final preview = await client.fetchAttachmentPreview(
    managedVaultBaseUrl: managedVaultBaseUrl,
    vaultId: vaultId,
    idToken: idToken,
    attachmentId: item.attachmentId,
  );
  if (_requiresAuthorizedContentOpen(
    preview.url,
    managedVaultBaseUrl: managedVaultBaseUrl,
  )) {
    final content = await client.fetchAttachmentContent(
      managedVaultBaseUrl: managedVaultBaseUrl,
      vaultId: vaultId,
      idToken: idToken,
      attachmentId: item.attachmentId,
      contentUrl: preview.url,
    );
    return contentOpener(item: item, content: content);
  }

  final launcher = externalLauncher ??
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
  return launcher(Uri.parse(preview.url));
}

bool _requiresAuthorizedContentOpen(
  String value, {
  required String managedVaultBaseUrl,
}) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) return true;
  final path = uri.path;
  if (!uri.hasScheme) return true;
  if (path.startsWith('/api/app/vault-proxy/')) return true;

  final baseUri = Uri.tryParse(managedVaultBaseUrl.trim());
  final sameManagedVaultOrigin = baseUri != null &&
      uri.scheme == baseUri.scheme &&
      uri.host == baseUri.host &&
      uri.port == baseUri.port;
  return sameManagedVaultOrigin && path.startsWith('/v1/vaults/');
}
