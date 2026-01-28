import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/backend/app_backend.dart';
import 'cloud_media_backup_client.dart';

enum CloudMediaBackupNetwork {
  offline,
  wifi,
  cellular,
  unknown,
}

final class CloudMediaBackupItem {
  const CloudMediaBackupItem({
    required this.attachmentSha256,
    required this.desiredVariant,
    required this.status,
    required this.attempts,
    required this.nextRetryAtMs,
  });

  final String attachmentSha256;
  final String desiredVariant;
  final String status;
  final int attempts;
  final int? nextRetryAtMs;
}

abstract class CloudMediaBackupStore {
  Future<List<CloudMediaBackupItem>> listDue({
    required int nowMs,
    int limit = 10,
  });

  Future<void> markUploaded({
    required String attachmentSha256,
    required int nowMs,
  });

  Future<void> markFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  });
}

final class CloudMediaBackupRunnerSettings {
  const CloudMediaBackupRunnerSettings({
    required this.enabled,
    required this.wifiOnly,
  });

  final bool enabled;
  final bool wifiOnly;
}

final class CloudMediaBackupRunResult {
  const CloudMediaBackupRunResult({
    required this.didUploadAny,
    required this.needsCellularConfirmation,
  });

  final bool didUploadAny;
  final bool needsCellularConfirmation;
}

typedef CloudMediaBackupNowMs = int Function();
typedef CloudMediaBackupNetworkProvider = Future<CloudMediaBackupNetwork>
    Function();

final class CloudMediaBackupRunner {
  CloudMediaBackupRunner({
    required this.store,
    required this.client,
    required this.settings,
    required this.getNetwork,
    CloudMediaBackupNowMs? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final CloudMediaBackupStore store;
  final CloudMediaBackupClient client;
  final CloudMediaBackupRunnerSettings settings;
  final CloudMediaBackupNetworkProvider getNetwork;
  final CloudMediaBackupNowMs _nowMs;

  Future<CloudMediaBackupRunResult> runOnce(
      {bool allowCellular = false}) async {
    if (!settings.enabled) {
      return const CloudMediaBackupRunResult(
        didUploadAny: false,
        needsCellularConfirmation: false,
      );
    }

    final nowMs = _nowMs();
    final network = await getNetwork();

    if (network == CloudMediaBackupNetwork.offline) {
      return const CloudMediaBackupRunResult(
        didUploadAny: false,
        needsCellularConfirmation: false,
      );
    }

    if (settings.wifiOnly &&
        network == CloudMediaBackupNetwork.cellular &&
        !allowCellular) {
      return const CloudMediaBackupRunResult(
        didUploadAny: false,
        needsCellularConfirmation: true,
      );
    }

    final due = await store.listDue(nowMs: nowMs);
    var didUploadAny = false;

    for (final item in due) {
      if (item.status == 'uploaded') continue;
      try {
        await client.upload(
          attachmentSha256: item.attachmentSha256,
          desiredVariant: item.desiredVariant,
        );
        await store.markUploaded(
          attachmentSha256: item.attachmentSha256,
          nowMs: nowMs,
        );
        didUploadAny = true;
      } catch (e) {
        final attempts = item.attempts + 1;
        final nextRetryAtMs = nowMs + _backoffMs(attempts);
        await store.markFailed(
          attachmentSha256: item.attachmentSha256,
          error: e.toString(),
          attempts: attempts,
          nextRetryAtMs: nextRetryAtMs,
          nowMs: nowMs,
        );
      }
    }

    return CloudMediaBackupRunResult(
      didUploadAny: didUploadAny,
      needsCellularConfirmation: false,
    );
  }

  static int _backoffMs(int attempts) {
    final clamped = attempts.clamp(1, 10);
    final seconds = 5 * (1 << (clamped - 1));
    return Duration(seconds: seconds).inMilliseconds;
  }
}

final class BackendCloudMediaBackupStore implements CloudMediaBackupStore {
  BackendCloudMediaBackupStore({
    required this.backend,
    required Uint8List sessionKey,
  }) : _sessionKey = Uint8List.fromList(sessionKey);

  final AppBackend backend;
  final Uint8List _sessionKey;

  @override
  Future<List<CloudMediaBackupItem>> listDue({
    required int nowMs,
    int limit = 10,
  }) async {
    final rows = await backend.listDueCloudMediaBackups(
      _sessionKey,
      nowMs: nowMs,
      limit: limit,
    );
    return rows
        .map(
          (r) => CloudMediaBackupItem(
            attachmentSha256: r.attachmentSha256,
            desiredVariant: r.desiredVariant,
            status: r.status,
            attempts: r.attempts,
            nextRetryAtMs: r.nextRetryAtMs,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markUploaded({
    required String attachmentSha256,
    required int nowMs,
  }) async {
    await backend.markCloudMediaBackupUploaded(
      _sessionKey,
      attachmentSha256: attachmentSha256,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    await backend.markCloudMediaBackupFailed(
      _sessionKey,
      attachmentSha256: attachmentSha256,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: error,
      nowMs: nowMs,
    );
  }
}

final class ManagedVaultCloudMediaBackupClient
    implements CloudMediaBackupClient {
  ManagedVaultCloudMediaBackupClient({
    required this.backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required this.baseUrl,
    required this.vaultId,
    required this.idToken,
  })  : _sessionKey = Uint8List.fromList(sessionKey),
        _syncKey = Uint8List.fromList(syncKey);

  final AppBackend backend;
  final Uint8List _sessionKey;
  final Uint8List _syncKey;
  final String baseUrl;
  final String vaultId;
  final String idToken;

  @override
  Future<void> upload({
    required String attachmentSha256,
    required String desiredVariant,
  }) async {
    final ok = await backend.syncManagedVaultUploadAttachmentBytes(
      _sessionKey,
      _syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
      sha256: attachmentSha256,
    );
    if (!ok) {
      throw StateError('missing_local_attachment_bytes:$attachmentSha256');
    }
  }
}

final class ConnectivityCloudMediaBackupNetworkProvider {
  ConnectivityCloudMediaBackupNetworkProvider({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<CloudMediaBackupNetwork> call() async {
    final results = await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return CloudMediaBackupNetwork.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return CloudMediaBackupNetwork.cellular;
    }
    if (results.contains(ConnectivityResult.none)) {
      return CloudMediaBackupNetwork.offline;
    }
    return CloudMediaBackupNetwork.unknown;
  }
}
