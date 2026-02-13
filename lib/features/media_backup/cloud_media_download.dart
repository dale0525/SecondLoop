import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import 'cloud_media_backup_runner.dart';

enum CloudMediaDownloadFailureReason {
  none,
  missingSyncConfig,
  networkOffline,
  cellularRestricted,
  backendMisconfigured,
  authRequired,
  remoteMissing,
  downloadFailed,
}

final class CloudMediaDownloadResult {
  const CloudMediaDownloadResult({
    required this.didDownload,
    required this.failureReason,
  });

  final bool didDownload;
  final CloudMediaDownloadFailureReason failureReason;

  bool get needsCellularConfirmation =>
      failureReason == CloudMediaDownloadFailureReason.cellularRestricted;
}

typedef CloudMediaDownloadNetworkProvider = Future<CloudMediaBackupNetwork>
    Function();

final class CloudMediaDownload {
  CloudMediaDownload({
    SyncConfigStore? configStore,
    CloudMediaDownloadNetworkProvider? networkProvider,
  })  : _configStore = configStore ?? SyncConfigStore(),
        _networkProvider = networkProvider ??
            ConnectivityCloudMediaBackupNetworkProvider().call;

  final SyncConfigStore _configStore;
  final CloudMediaDownloadNetworkProvider _networkProvider;

  static final Map<String, Future<CloudMediaDownloadResult>>
      _inFlightDownloads = <String, Future<CloudMediaDownloadResult>>{};

  Future<bool> downloadAttachmentBytesFromConfiguredSync(
    BuildContext context, {
    required String sha256,
    bool allowCellular = false,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final idTokenGetter =
        CloudAuthScope.maybeOf(context)?.controller.getIdToken;
    final result = await downloadAttachmentBytesFromConfiguredSyncWithPolicy(
      backend: backend,
      sessionKey: sessionKey,
      idTokenGetter: idTokenGetter,
      sha256: sha256,
      allowCellular: allowCellular,
    );
    return result.didDownload;
  }

  Future<CloudMediaDownloadResult>
      downloadAttachmentBytesFromConfiguredSyncWithPolicy({
    required AppBackend backend,
    required Uint8List sessionKey,
    Future<String?> Function()? idTokenGetter,
    required String sha256,
    bool allowCellular = false,
  }) async {
    final config = await _configStore.loadConfiguredSync();
    if (config == null) {
      return _failed(CloudMediaDownloadFailureReason.missingSyncConfig);
    }

    if (config.backendType != SyncBackendType.localDir) {
      final wifiOnly = await _configStore.readMediaDownloadsWifiOnly();
      if (wifiOnly && !allowCellular) {
        final network = await _safeNetwork();
        if (network == CloudMediaBackupNetwork.offline) {
          return _failed(CloudMediaDownloadFailureReason.networkOffline);
        }
        if (network != CloudMediaBackupNetwork.wifi) {
          return _failed(CloudMediaDownloadFailureReason.cellularRestricted);
        }
      }
    }

    switch (config.backendType) {
      case SyncBackendType.webdav:
        final baseUrl = config.baseUrl;
        if (baseUrl == null || baseUrl.trim().isEmpty) {
          return _failed(CloudMediaDownloadFailureReason.backendMisconfigured);
        }
        final dedupeKey = _downloadRequestKey(
          config: config,
          sha256: sha256,
          allowCellular: allowCellular,
        );
        return _runDedupedDownload(
          dedupeKey: dedupeKey,
          action: () => _downloadWithErrorMapping(
            () => backend.syncWebdavDownloadAttachmentBytes(
              sessionKey,
              config.syncKey,
              baseUrl: baseUrl,
              username: config.username,
              password: config.password,
              remoteRoot: config.remoteRoot,
              sha256: sha256,
            ),
          ),
        );
      case SyncBackendType.localDir:
        final localDir = config.localDir;
        if (localDir == null || localDir.trim().isEmpty) {
          return _failed(CloudMediaDownloadFailureReason.backendMisconfigured);
        }
        final dedupeKey = _downloadRequestKey(
          config: config,
          sha256: sha256,
          allowCellular: allowCellular,
        );
        return _runDedupedDownload(
          dedupeKey: dedupeKey,
          action: () => _downloadWithErrorMapping(
            () => backend.syncLocaldirDownloadAttachmentBytes(
              sessionKey,
              config.syncKey,
              localDir: localDir,
              remoteRoot: config.remoteRoot,
              sha256: sha256,
            ),
          ),
        );
      case SyncBackendType.managedVault:
        final baseUrl = config.baseUrl;
        if (baseUrl == null || baseUrl.trim().isEmpty) {
          return _failed(CloudMediaDownloadFailureReason.backendMisconfigured);
        }
        final getter = idTokenGetter;
        if (getter == null) {
          return _failed(CloudMediaDownloadFailureReason.authRequired);
        }
        final idToken = await getter();
        if (idToken == null || idToken.trim().isEmpty) {
          return _failed(CloudMediaDownloadFailureReason.authRequired);
        }
        final dedupeKey = _downloadRequestKey(
          config: config,
          sha256: sha256,
          allowCellular: allowCellular,
        );
        return _runDedupedDownload(
          dedupeKey: dedupeKey,
          action: () => _downloadWithErrorMapping(
            () => backend.syncManagedVaultDownloadAttachmentBytes(
              sessionKey,
              config.syncKey,
              baseUrl: baseUrl,
              vaultId: config.remoteRoot,
              idToken: idToken,
              sha256: sha256,
            ),
          ),
        );
    }
  }

  String _downloadRequestKey({
    required SyncConfig config,
    required String sha256,
    required bool allowCellular,
  }) {
    final backend = switch (config.backendType) {
      SyncBackendType.webdav => 'webdav',
      SyncBackendType.localDir => 'localdir',
      SyncBackendType.managedVault => 'managedvault',
    };

    return [
      backend,
      config.baseUrl?.trim() ?? '',
      config.localDir?.trim() ?? '',
      config.remoteRoot.trim(),
      allowCellular ? '1' : '0',
      sha256.trim(),
    ].join('|');
  }

  Future<CloudMediaDownloadResult> _runDedupedDownload({
    required String dedupeKey,
    required Future<CloudMediaDownloadResult> Function() action,
  }) async {
    final existing = _inFlightDownloads[dedupeKey];
    if (existing != null) {
      return existing;
    }

    final future = action();
    _inFlightDownloads[dedupeKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightDownloads[dedupeKey], future)) {
        _inFlightDownloads.remove(dedupeKey);
      }
    }
  }

  Future<CloudMediaDownloadResult> _downloadWithErrorMapping(
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return _downloaded();
    } catch (e) {
      if (_isRemoteMissingError(e)) {
        return _failed(CloudMediaDownloadFailureReason.remoteMissing);
      }
      return _failed(CloudMediaDownloadFailureReason.downloadFailed);
    }
  }

  bool _isRemoteMissingError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('not found')) return true;
    if (message.contains('http 404')) return true;
    return false;
  }

  CloudMediaDownloadResult _downloaded() {
    return const CloudMediaDownloadResult(
      didDownload: true,
      failureReason: CloudMediaDownloadFailureReason.none,
    );
  }

  CloudMediaDownloadResult _failed(CloudMediaDownloadFailureReason reason) {
    return CloudMediaDownloadResult(
      didDownload: false,
      failureReason: reason,
    );
  }

  Future<CloudMediaBackupNetwork> _safeNetwork() async {
    try {
      return await _networkProvider();
    } catch (_) {
      return CloudMediaBackupNetwork.unknown;
    }
  }
}
