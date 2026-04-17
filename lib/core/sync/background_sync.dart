import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../ai/ai_routing.dart';
import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_auth_access.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../cloud/firebase_identity_toolkit.dart';
import '../../features/media_enrichment/media_enrichment_runner.dart';
import '../../features/media_backup/cloud_media_backup_runner.dart';
import 'background_sync_orchestrator.dart';
import 'sync_config_store.dart';
import 'sync_diagnostics.dart';
import 'sync_engine.dart';
import 'sync_key_manager.dart';

const _kAppId = String.fromEnvironment(
  'SECONDLOOP_APP_ID',
  defaultValue: 'com.secondloop.secondloop',
);
const _kWorkmanagerTaskId = '$_kAppId.backgroundSync';
const _kWorkmanagerUniqueName = _kWorkmanagerTaskId;
const _kWorkmanagerTaskName = _kWorkmanagerTaskId;

const Duration _kBackgroundSyncBackoffBase = Duration(minutes: 1);
const Duration _kBackgroundSyncBackoffMax = Duration(minutes: 60);

@pragma('vm:entry-point')
void backgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    ui.DartPluginRegistrant.ensureInitialized();
    return BackgroundSync.runOnce(taskName: task);
  });
}

enum _BackgroundOpStatus {
  success,
  skipped,
  failure,
}

final class _BackgroundSyncOpResult {
  const _BackgroundSyncOpResult._({
    required this.status,
    required this.applied,
    required this.durationMs,
    this.statusCode,
    this.errorCode,
    this.errorMessage,
    this.userMessage,
    this.retryable = false,
  });

  factory _BackgroundSyncOpResult.success({
    required int applied,
    required int durationMs,
  }) {
    return _BackgroundSyncOpResult._(
      status: _BackgroundOpStatus.success,
      applied: applied,
      durationMs: durationMs,
    );
  }

  factory _BackgroundSyncOpResult.skipped({
    required int durationMs,
    String? userMessage,
  }) {
    return _BackgroundSyncOpResult._(
      status: _BackgroundOpStatus.skipped,
      applied: 0,
      durationMs: durationMs,
      userMessage: userMessage,
    );
  }

  factory _BackgroundSyncOpResult.failure({
    required int durationMs,
    required bool retryable,
    int? statusCode,
    String? errorCode,
    String? errorMessage,
    String? userMessage,
  }) {
    return _BackgroundSyncOpResult._(
      status: _BackgroundOpStatus.failure,
      applied: 0,
      durationMs: durationMs,
      statusCode: statusCode,
      errorCode: errorCode,
      errorMessage: errorMessage,
      userMessage: userMessage,
      retryable: retryable,
    );
  }

  final _BackgroundOpStatus status;
  final int applied;
  final int durationMs;
  final int? statusCode;
  final String? errorCode;
  final String? errorMessage;
  final String? userMessage;
  final bool retryable;
}

final class BackgroundSync {
  static const workmanagerUniqueName = _kWorkmanagerUniqueName;
  static const workmanagerTaskName = _kWorkmanagerTaskName;

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<void> init() async {
    if (!isSupported) return;
    try {
      await Workmanager().initialize(
        backgroundSyncCallbackDispatcher,
        isInDebugMode: kDebugMode,
      );
    } catch (_) {
      return;
    }
  }

  static Future<void> refreshSchedule({
    AppBackend? backend,
    SyncConfigStore? configStore,
    BackgroundSyncScheduler? scheduler,
  }) async {
    if (!isSupported) return;

    final store = configStore ?? SyncConfigStore();
    final backendForKey = backend ?? NativeAppBackend();
    final sched = scheduler ?? WorkmanagerBackgroundSyncScheduler();

    final orchestrator = BackgroundSyncOrchestrator(
      readAutoEnabled: store.readAutoEnabled,
      loadConfig: store.loadConfiguredSync,
      hasSavedSessionKey: () async =>
          (await backendForKey.loadSavedSessionKey()) != null,
      scheduler: sched,
    );

    await orchestrator.refreshSchedule();
  }

  static Future<bool> runOnce({required String taskName}) async {
    if (taskName != workmanagerTaskName) return true;

    final store = SyncConfigStore();
    final backend = NativeAppBackend();
    CloudAuthControllerImpl? cloudAuth;
    final scheduler = WorkmanagerBackgroundSyncScheduler();

    Future<void> rescheduleIfNeeded() async {
      if (defaultTargetPlatform != TargetPlatform.iOS) return;
      await refreshSchedule(
        backend: backend,
        configStore: store,
        scheduler: scheduler,
      );
    }

    final enabled = await store.readAutoEnabled();
    if (!enabled) {
      await rescheduleIfNeeded();
      return true;
    }

    final config = await store.loadConfiguredSync();
    if (config == null) {
      await rescheduleIfNeeded();
      return true;
    }

    final backgroundDiagEnabled = await store.readSyncBackgroundDiagV1Enabled();
    final backoffEnabled = await store.readSyncBackoffV1Enabled();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (backoffEnabled) {
      final backoffState = await store.readBackgroundSyncBackoffState(
        backendType: config.backendType,
      );
      if (backoffState != null && nowMs < backoffState.nextAllowedAtMs) {
        await rescheduleIfNeeded();
        return true;
      }
    }

    final sessionKey = await backend.loadSavedSessionKey();
    if (sessionKey == null || sessionKey.length != 32) {
      await rescheduleIfNeeded();
      return true;
    }
    SyncKeyManager.setSessionKey(sessionKey);

    final wifiOnly = await store.readAutoWifiOnly();
    if (wifiOnly) {
      try {
        final network =
            await ConnectivityCloudMediaBackupNetworkProvider().call();
        if (network == CloudMediaBackupNetwork.cellular ||
            network == CloudMediaBackupNetwork.offline) {
          await rescheduleIfNeeded();
          return true;
        }
      } catch (_) {
        // Best-effort: if connectivity plugin is unavailable in this isolate,
        // fall back to running sync as usual.
      }
    }

    await backend.init();

    final mediaUploadsEnabled = await store.readCloudMediaBackupEnabled();

    try {
      String? idToken;
      const webApiKey = String.fromEnvironment(
        'SECONDLOOP_FIREBASE_WEB_API_KEY',
        defaultValue: '',
      );
      if (webApiKey.trim().isNotEmpty) {
        cloudAuth ??= CloudAuthControllerImpl(
          identityToolkit: FirebaseIdentityToolkitHttp(webApiKey: webApiKey),
        );
        try {
          idToken = await readCloudAuthIdToken(
            cloudAuth,
            mode: CloudAuthAccessMode.background,
          );
        } catch (_) {
          idToken = null;
        }
      }

      final pushResult = await _pushOnce(
        backend: backend,
        sessionKey: sessionKey,
        config: config,
        managedVaultIdToken: idToken,
      );
      final pullResult = await _pullOnce(
        backend: backend,
        sessionKey: sessionKey,
        config: config,
        managedVaultIdToken: idToken,
      );

      final retryableFailure = switch ((
        pushResult.retryable,
        pullResult.retryable,
      )) {
        (true, _) => pushResult,
        (_, true) => pullResult,
        _ => null,
      };

      final retryCount = backoffEnabled
          ? await _updateBackoffState(
              store: store,
              backendType: config.backendType,
              nowMs: DateTime.now().millisecondsSinceEpoch,
              retryableFailure: retryableFailure,
            )
          : null;
      if (!backoffEnabled) {
        await store.writeBackgroundSyncBackoffState(
          null,
          backendType: config.backendType,
        );
      }

      if (backgroundDiagEnabled) {
        await _writeBackgroundResult(
          store: store,
          backendType: config.backendType,
          direction: SyncBackgroundDirection.pull,
          result: pullResult,
          retryCount: pullResult.retryable ? retryCount : null,
        );
        await _writeBackgroundResult(
          store: store,
          backendType: config.backendType,
          direction: SyncBackgroundDirection.push,
          result: pushResult,
          retryCount: pushResult.retryable ? retryCount : null,
        );
      }

      final allowManagedVaultMediaUploads =
          config.backendType != SyncBackendType.managedVault ||
              !shouldSkipManagedVaultMediaUploadsAfterPushFailure(
                statusCode: pushResult.statusCode,
                errorCode: pushResult.errorCode,
              );

      if (mediaUploadsEnabled && allowManagedVaultMediaUploads) {
        final wifiOnly = await store.readCloudMediaBackupWifiOnly();
        switch (config.backendType) {
          case SyncBackendType.webdav:
            final baseUrl = config.baseUrl;
            if (baseUrl != null && baseUrl.trim().isNotEmpty) {
              final runner = CloudMediaBackupRunner(
                store: BackendCloudMediaBackupStore(
                  backend: backend,
                  sessionKey: sessionKey,
                ),
                client: WebDavCloudMediaBackupClient(
                  backend: backend,
                  sessionKey: sessionKey,
                  syncKey: config.syncKey,
                  baseUrl: baseUrl,
                  username: config.username,
                  password: config.password,
                  remoteRoot: config.remoteRoot,
                ),
                settings: CloudMediaBackupRunnerSettings(
                  enabled: true,
                  wifiOnly: wifiOnly,
                ),
                getNetwork: ConnectivityCloudMediaBackupNetworkProvider().call,
              );
              await runner.runOnce(allowCellular: false);
            }
            break;
          case SyncBackendType.managedVault:
            final token = idToken;
            if (token != null && token.trim().isNotEmpty) {
              final runner = CloudMediaBackupRunner(
                store: BackendCloudMediaBackupStore(
                  backend: backend,
                  sessionKey: sessionKey,
                ),
                client: ManagedVaultCloudMediaBackupClient(
                  backend: backend,
                  sessionKey: sessionKey,
                  syncKey: config.syncKey,
                  baseUrl: config.baseUrl ?? '',
                  vaultId: config.remoteRoot,
                  idToken: token,
                ),
                settings: CloudMediaBackupRunnerSettings(
                  enabled: true,
                  wifiOnly: wifiOnly,
                ),
                getNetwork: ConnectivityCloudMediaBackupNetworkProvider().call,
              );
              await runner.runOnce(allowCellular: false);
            }
            break;
          case SyncBackendType.localDir:
            break;
        }
      }

      final token = idToken;
      if (token != null && token.trim().isNotEmpty) {
        final baseUrl = CloudGatewayConfig.defaultConfig.baseUrl;
        if (baseUrl.trim().isNotEmpty) {
          final runner = MediaEnrichmentRunner(
            store: BackendMediaEnrichmentStore(
              backend: backend,
              sessionKey: sessionKey,
            ),
            client: CloudGatewayMediaEnrichmentClient(
              backend: backend,
              gatewayBaseUrl: baseUrl,
              idToken: token,
              annotationModelName: 'gpt-4o-mini',
            ),
            settings: const MediaEnrichmentRunnerSettings(
              annotationEnabled: false,
              annotationWifiOnly: true,
            ),
            getNetwork: ConnectivityMediaEnrichmentNetworkProvider().call,
          );
          try {
            await runner.runOnce(allowAnnotationCellular: false);
          } catch (_) {
            // Best-effort: enrichment should not block sync.
          }
        }
      }

      await rescheduleIfNeeded();
      return true;
    } catch (_) {
      await rescheduleIfNeeded();
      return false;
    } finally {
      SyncKeyManager.setSessionKey(null);
      cloudAuth?.dispose();
    }
  }

  static Future<_BackgroundSyncOpResult> _pullOnce({
    required AppBackend backend,
    required Uint8List sessionKey,
    required SyncConfig config,
    required String? managedVaultIdToken,
  }) async {
    final startMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final applied = await switch (config.backendType) {
        SyncBackendType.webdav => backend.syncWebdavPull(
            sessionKey,
            config.syncKey,
            baseUrl: config.baseUrl ?? '',
            username: config.username,
            password: config.password,
            remoteRoot: config.remoteRoot,
          ),
        SyncBackendType.localDir => backend.syncLocaldirPull(
            sessionKey,
            config.syncKey,
            localDir: config.localDir ?? '',
            remoteRoot: config.remoteRoot,
          ),
        SyncBackendType.managedVault => () async {
            final idToken = managedVaultIdToken;
            if (idToken == null || idToken.trim().isEmpty) {
              return -1;
            }
            return backend.syncManagedVaultPull(
              sessionKey,
              config.syncKey,
              baseUrl: config.baseUrl ?? '',
              vaultId: config.remoteRoot,
              idToken: idToken,
            );
          }(),
      };
      final durationMs = DateTime.now().millisecondsSinceEpoch - startMs;
      if (applied < 0) {
        return _BackgroundSyncOpResult.skipped(
          durationMs: durationMs,
          userMessage: 'Sign in required for cloud sync.',
        );
      }
      return _BackgroundSyncOpResult.success(
        applied: applied,
        durationMs: durationMs,
      );
    } catch (error) {
      return _failureFromError(
        error,
        durationMs: DateTime.now().millisecondsSinceEpoch - startMs,
      );
    }
  }

  static Future<_BackgroundSyncOpResult> _pushOnce({
    required AppBackend backend,
    required Uint8List sessionKey,
    required SyncConfig config,
    required String? managedVaultIdToken,
  }) async {
    final startMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final pushed = await switch (config.backendType) {
        SyncBackendType.webdav => backend.syncWebdavPushOpsOnly(
            sessionKey,
            config.syncKey,
            baseUrl: config.baseUrl ?? '',
            username: config.username,
            password: config.password,
            remoteRoot: config.remoteRoot,
          ),
        SyncBackendType.localDir => backend.syncLocaldirPush(
            sessionKey,
            config.syncKey,
            localDir: config.localDir ?? '',
            remoteRoot: config.remoteRoot,
          ),
        SyncBackendType.managedVault => () async {
            final idToken = managedVaultIdToken;
            if (idToken == null || idToken.trim().isEmpty) {
              return -1;
            }
            return backend.syncManagedVaultPushOpsOnly(
              sessionKey,
              config.syncKey,
              baseUrl: config.baseUrl ?? '',
              vaultId: config.remoteRoot,
              idToken: idToken,
            );
          }(),
      };
      final durationMs = DateTime.now().millisecondsSinceEpoch - startMs;
      if (pushed < 0) {
        return _BackgroundSyncOpResult.skipped(
          durationMs: durationMs,
          userMessage: 'Sign in required for cloud sync.',
        );
      }
      return _BackgroundSyncOpResult.success(
        applied: pushed,
        durationMs: durationMs,
      );
    } catch (error) {
      return _failureFromError(
        error,
        durationMs: DateTime.now().millisecondsSinceEpoch - startMs,
      );
    }
  }

  static _BackgroundSyncOpResult _failureFromError(
    Object error, {
    required int durationMs,
  }) {
    final statusCode = parseHttpStatusFromError(error);
    final errorCode = parseCloudErrorCodeFromError(error);
    final errorMessage = error.toString();
    return _BackgroundSyncOpResult.failure(
      durationMs: durationMs,
      retryable: isRetryableBackgroundSyncFailure(
        statusCode: statusCode,
        errorCode: errorCode,
        message: errorMessage,
      ),
      statusCode: statusCode,
      errorCode: errorCode,
      errorMessage: errorMessage,
      userMessage: userReadableSyncErrorMessage(
        statusCode: statusCode,
        errorCode: errorCode,
      ),
    );
  }

  @visibleForTesting
  static Duration retryBackoffDelayForFailureCount(
    int failureCount, {
    Duration base = _kBackgroundSyncBackoffBase,
    Duration max = _kBackgroundSyncBackoffMax,
  }) {
    if (failureCount <= 0) return Duration.zero;
    final exponent = (failureCount - 1).clamp(0, 30);
    final multiplier = 1 << exponent;
    final delayMs = base.inMilliseconds * multiplier;
    final cappedMs =
        delayMs > max.inMilliseconds ? max.inMilliseconds : delayMs;
    return Duration(milliseconds: cappedMs);
  }

  @visibleForTesting
  static bool isRetryableBackgroundSyncFailure({
    int? statusCode,
    String? errorCode,
    String? message,
  }) {
    if (statusCode != null) {
      if (statusCode == 401 || statusCode == 408 || statusCode == 429) {
        return true;
      }
      if (statusCode >= 500) return true;
      if (statusCode == 402) return false;
      if (statusCode == 403) {
        if (errorCode == 'grace_readonly' ||
            errorCode == 'storage_quota_exceeded') {
          return false;
        }
        return false;
      }
    }

    final normalized = (message ?? '').toLowerCase();
    if (normalized.contains('socketexception') ||
        normalized.contains('timeout') ||
        normalized.contains('timed out') ||
        normalized.contains('network')) {
      return true;
    }
    return false;
  }

  @visibleForTesting
  static String userReadableSyncErrorMessage({
    int? statusCode,
    String? errorCode,
  }) {
    if (statusCode == 401) {
      return 'Sign-in expired. Please sign in again.';
    }
    if (statusCode == 402) {
      return 'Cloud subscription required to continue sync.';
    }
    if (statusCode == 403 && errorCode == 'grace_readonly') {
      return 'Cloud sync is read-only during grace period.';
    }
    if (statusCode == 403 && errorCode == 'storage_quota_exceeded') {
      return 'Cloud storage quota exceeded. Please free space or upgrade.';
    }
    if (statusCode == 429) {
      return 'Sync is being throttled. Retrying later.';
    }
    if (statusCode != null && statusCode >= 500) {
      return 'Server is temporarily unavailable. Retrying later.';
    }
    return 'Sync failed. Retrying automatically when possible.';
  }

  @visibleForTesting
  static bool shouldSkipManagedVaultMediaUploadsAfterPushFailure({
    int? statusCode,
    String? errorCode,
  }) {
    if (statusCode == 402) return true;
    return statusCode == 403 &&
        (errorCode == 'grace_readonly' ||
            errorCode == 'storage_quota_exceeded');
  }

  static Future<int?> _updateBackoffState({
    required SyncConfigStore store,
    required SyncBackendType backendType,
    required int nowMs,
    required _BackgroundSyncOpResult? retryableFailure,
  }) async {
    if (retryableFailure == null) {
      await store.writeBackgroundSyncBackoffState(
        null,
        backendType: backendType,
      );
      return null;
    }
    final previous = await store.readBackgroundSyncBackoffState(
      backendType: backendType,
    );
    final retryCount = (previous?.retryCount ?? 0) + 1;
    final delay = retryBackoffDelayForFailureCount(retryCount);
    await store.writeBackgroundSyncBackoffState(
      SyncBackgroundBackoffState(
        backendType: backendType,
        retryCount: retryCount,
        nextAllowedAtMs: nowMs + delay.inMilliseconds,
        updatedAtMs: nowMs,
        lastStatusCode: retryableFailure.statusCode,
        lastErrorCode: retryableFailure.errorCode,
      ),
      backendType: backendType,
    );
    return retryCount;
  }

  static Future<void> _writeBackgroundResult({
    required SyncConfigStore store,
    required SyncBackendType backendType,
    required SyncBackgroundDirection direction,
    required _BackgroundSyncOpResult result,
    required int? retryCount,
  }) async {
    final status = switch (result.status) {
      _BackgroundOpStatus.success => SyncBackgroundResultStatus.success,
      _BackgroundOpStatus.skipped => SyncBackgroundResultStatus.skipped,
      _BackgroundOpStatus.failure => SyncBackgroundResultStatus.failure,
    };
    await store.writeBackgroundSyncResult(
      SyncBackgroundResult(
        backendType: backendType,
        direction: direction,
        status: status,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        statusCode: result.statusCode,
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
        userMessage: result.userMessage,
        retryCount: retryCount,
        durationMs: result.durationMs,
      ),
      backendType: backendType,
    );
  }
}

final class WorkmanagerBackgroundSyncScheduler
    implements BackgroundSyncScheduler {
  @override
  Future<void> schedulePeriodicSync({required Duration frequency}) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await Workmanager()
            .cancelByUniqueName(BackgroundSync.workmanagerUniqueName);
        await Workmanager().registerOneOffTask(
          BackgroundSync.workmanagerUniqueName,
          BackgroundSync.workmanagerTaskName,
          initialDelay: frequency,
          existingWorkPolicy: ExistingWorkPolicy.replace,
          constraints: Constraints(
            networkType: NetworkType.connected,
          ),
        );
        return;
      }

      await Workmanager().registerPeriodicTask(
        BackgroundSync.workmanagerUniqueName,
        BackgroundSync.workmanagerTaskName,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        frequency: frequency,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> cancelPeriodicSync() async {
    try {
      await Workmanager()
          .cancelByUniqueName(BackgroundSync.workmanagerUniqueName);
    } catch (_) {
      return;
    }
  }
}
