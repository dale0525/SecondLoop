import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import 'cloud_media_backup_runner.dart';

final class CloudMediaDownloadResult {
  const CloudMediaDownloadResult({
    required this.didDownload,
    required this.needsCellularConfirmation,
  });

  final bool didDownload;
  final bool needsCellularConfirmation;
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
      return const CloudMediaDownloadResult(
        didDownload: false,
        needsCellularConfirmation: false,
      );
    }

    if (config.backendType != SyncBackendType.localDir) {
      final wifiOnly = await _configStore.readMediaDownloadsWifiOnly();
      if (wifiOnly && !allowCellular) {
        final network = await _safeNetwork();
        if (network == CloudMediaBackupNetwork.offline) {
          return const CloudMediaDownloadResult(
            didDownload: false,
            needsCellularConfirmation: false,
          );
        }
        if (network != CloudMediaBackupNetwork.wifi) {
          return const CloudMediaDownloadResult(
            didDownload: false,
            needsCellularConfirmation: true,
          );
        }
      }
    }

    switch (config.backendType) {
      case SyncBackendType.webdav:
        final baseUrl = config.baseUrl;
        if (baseUrl == null || baseUrl.trim().isEmpty) {
          return const CloudMediaDownloadResult(
            didDownload: false,
            needsCellularConfirmation: false,
          );
        }
        final dedupeKey = _downloadRequestKey(
          config: config,
          sha256: sha256,
          allowCellular: allowCellular,
        );
        return _runDedupedDownload(
          dedupeKey: dedupeKey,
          action: () async {
            await backend.syncWebdavDownloadAttachmentBytes(
              sessionKey,
              config.syncKey,
              baseUrl: baseUrl,
              username: config.username,
              password: config.password,
              remoteRoot: config.remoteRoot,
              sha256: sha256,
            );
            return const CloudMediaDownloadResult(
              didDownload: true,
              needsCellularConfirmation: false,
            );
          },
        );
      case SyncBackendType.localDir:
        final localDir = config.localDir;
        if (localDir == null || localDir.trim().isEmpty) {
          return const CloudMediaDownloadResult(
            didDownload: false,
            needsCellularConfirmation: false,
          );
        }
        final dedupeKey = _downloadRequestKey(
          config: config,
          sha256: sha256,
          allowCellular: allowCellular,
        );
        return _runDedupedDownload(
          dedupeKey: dedupeKey,
          action: () async {
            await backend.syncLocaldirDownloadAttachmentBytes(
              sessionKey,
              config.syncKey,
              localDir: localDir,
              remoteRoot: config.remoteRoot,
              sha256: sha256,
            );
            return const CloudMediaDownloadResult(
              didDownload: true,
              needsCellularConfirmation: false,
            );
          },
        );
      case SyncBackendType.managedVault:
        final baseUrl = config.baseUrl;
        if (baseUrl == null || baseUrl.trim().isEmpty) {
          return const CloudMediaDownloadResult(
            didDownload: false,
            needsCellularConfirmation: false,
          );
        }
        final getter = idTokenGetter;
        if (getter == null) {
          return const CloudMediaDownloadResult(
            didDownload: false,
            needsCellularConfirmation: false,
          );
        }
        final idToken = await getter();
        if (idToken == null || idToken.trim().isEmpty) {
          return const CloudMediaDownloadResult(
            didDownload: false,
            needsCellularConfirmation: false,
          );
        }
        final dedupeKey = _downloadRequestKey(
          config: config,
          sha256: sha256,
          allowCellular: allowCellular,
        );
        return _runDedupedDownload(
          dedupeKey: dedupeKey,
          action: () async {
            await backend.syncManagedVaultDownloadAttachmentBytes(
              sessionKey,
              config.syncKey,
              baseUrl: baseUrl,
              vaultId: config.remoteRoot,
              idToken: idToken,
              sha256: sha256,
            );
            return const CloudMediaDownloadResult(
              didDownload: true,
              needsCellularConfirmation: false,
            );
          },
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

  Future<CloudMediaBackupNetwork> _safeNetwork() async {
    try {
      return await _networkProvider();
    } catch (_) {
      return CloudMediaBackupNetwork.unknown;
    }
  }
}
