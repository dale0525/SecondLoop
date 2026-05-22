import '../../core/cloud/vault_attachments_client.dart';
import 'vault_attachment_content_opener_stub.dart'
    if (dart.library.io) 'vault_attachment_content_opener_io.dart'
    if (dart.library.html) 'vault_attachment_content_opener_web.dart' as impl;

typedef VaultAttachmentContentOpener = Future<bool> Function({
  required VaultAttachmentUsageItem item,
  required VaultAttachmentContent content,
});

Future<bool> openVaultAttachmentContent({
  required VaultAttachmentUsageItem item,
  required VaultAttachmentContent content,
}) {
  return impl.openVaultAttachmentContent(item: item, content: content);
}
