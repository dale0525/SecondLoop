import 'package:flutter/widgets.dart';

import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';

final class CloudMediaDownload {
  CloudMediaDownload({SyncConfigStore? configStore})
      : _configStore = configStore ?? SyncConfigStore();

  final SyncConfigStore _configStore;

  Future<bool> downloadAttachmentBytesFromConfiguredSync(
    BuildContext context, {
    required String sha256,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final idTokenGetter =
        CloudAuthScope.maybeOf(context)?.controller.getIdToken;

    final config = await _configStore.loadConfiguredSync();
    if (config == null) return false;

    switch (config.backendType) {
      case SyncBackendType.webdav:
        final baseUrl = config.baseUrl;
        if (baseUrl == null || baseUrl.trim().isEmpty) return false;
        await backend.syncWebdavDownloadAttachmentBytes(
          sessionKey,
          config.syncKey,
          baseUrl: baseUrl,
          username: config.username,
          password: config.password,
          remoteRoot: config.remoteRoot,
          sha256: sha256,
        );
        return true;
      case SyncBackendType.localDir:
        final localDir = config.localDir;
        if (localDir == null || localDir.trim().isEmpty) return false;
        await backend.syncLocaldirDownloadAttachmentBytes(
          sessionKey,
          config.syncKey,
          localDir: localDir,
          remoteRoot: config.remoteRoot,
          sha256: sha256,
        );
        return true;
      case SyncBackendType.managedVault:
        final baseUrl = config.baseUrl;
        if (baseUrl == null || baseUrl.trim().isEmpty) return false;
        final getter = idTokenGetter;
        if (getter == null) return false;
        final idToken = await getter();
        if (idToken == null || idToken.trim().isEmpty) return false;
        await backend.syncManagedVaultDownloadAttachmentBytes(
          sessionKey,
          config.syncKey,
          baseUrl: baseUrl,
          vaultId: config.remoteRoot,
          idToken: idToken,
          sha256: sha256,
        );
        return true;
    }
  }
}
