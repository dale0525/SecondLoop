import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../core/ai/ai_routing.dart';
import '../core/backend/app_backend.dart';
import '../core/backend/cloud_web_backend.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/session/session_scope.dart';
import '../features/attachments/attachment_viewer_page.dart';
import '../i18n/strings.g.dart';
import '../src/rust/db.dart';
import 'web_app_service.dart';

String? webVaultIdForController(CloudAuthController controller) {
  final uid = controller.uid?.trim();
  if (uid == null || uid.isEmpty) return null;
  return uid;
}

Attachment webAttachmentFromVaultItem(WebVaultAttachmentItem item) {
  return Attachment(
    sha256: item.primarySha256,
    mimeType: item.mimeType,
    path: 'vault/${item.primarySha256}.bin',
    byteLen: PlatformInt64Util.from(item.byteLen),
    createdAtMs: PlatformInt64Util.from(item.createdAtMs ?? 0),
  );
}

String formatWebCloudError(BuildContext context, Object error) {
  final status = parseHttpStatusFromError(error);
  final code = parseCloudErrorCodeFromError(error);
  if (status == 402 || code == 'payment_required') {
    return context.t.sync.cloudManagedVault.paymentRequired;
  }
  if (status == 403 && code == 'email_not_verified') {
    return context.t.chat.cloudGateway.emailNotVerified;
  }
  if (status == 403 && code == 'storage_quota_exceeded') {
    return context.t.sync.cloudManagedVault.storageQuotaExceeded;
  }
  if (status == 429) {
    return context.t.chat.cloudGateway.errors.rateLimited;
  }
  if (status != null && status >= 500) {
    return context.t.sync.cloudManagedVault.serverUnavailable;
  }
  if ('$error'.contains('attachment_too_large_for_web')) {
    return context.t.app.web.files.messages.attachmentTooLarge;
  }
  return '$error';
}

Future<Uint8List?> readPlatformFileBytes(PlatformFile file) async {
  final directBytes = file.bytes;
  if (directBytes != null) {
    return Uint8List.fromList(directBytes);
  }

  final readStream = file.readStream;
  if (readStream == null) return null;

  final builder = BytesBuilder(copy: false);
  await for (final chunk in readStream) {
    if (chunk.isNotEmpty) {
      builder.add(chunk);
    }
  }
  return builder.takeBytes();
}

Future<void> openWebVaultAttachmentViewer({
  required BuildContext context,
  required WebAppService service,
  required CloudAuthController authController,
  required CloudWebBackend chatBackend,
  required Uint8List sessionKey,
  required WebVaultAttachmentItem item,
}) async {
  final idToken = await authController.getIdToken();
  final vaultId = webVaultIdForController(authController);
  if (idToken == null || idToken.isEmpty || vaultId == null) return;
  if (!context.mounted) return;

  final bytes = await service.fetchVaultAttachmentBytes(
    idToken: idToken,
    vaultId: vaultId,
    sha256: item.primarySha256,
  );
  final attachment = webAttachmentFromVaultItem(item);
  final attachmentBytes =
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  chatBackend.rememberAttachment(
    attachment,
    bytes: attachmentBytes,
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => SessionScope(
        sessionKey: sessionKey,
        lock: () {},
        child: AppBackendScope(
          backend: chatBackend,
          child: AttachmentViewerPage(
            attachment: attachment,
            isWebOverride: true,
          ),
        ),
      ),
    ),
  );
}
