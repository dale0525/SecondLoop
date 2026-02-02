import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../cloud/firebase_identity_toolkit.dart';
import '../../features/media_enrichment/media_enrichment_runner.dart';
import '../../features/media_backup/cloud_media_backup_runner.dart';
import 'background_sync_orchestrator.dart';
import 'sync_config_store.dart';
import 'sync_engine.dart';

const _kWorkmanagerTaskId = 'com.secondloop.secondloop.backgroundSync';
const _kWorkmanagerUniqueName = _kWorkmanagerTaskId;
const _kWorkmanagerTaskName = _kWorkmanagerTaskId;

@pragma('vm:entry-point')
void backgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    ui.DartPluginRegistrant.ensureInitialized();
    return BackgroundSync.runOnce(taskName: task);
  });
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

    final sessionKey = await backend.loadSavedSessionKey();
    if (sessionKey == null || sessionKey.length != 32) {
      await rescheduleIfNeeded();
      return true;
    }

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
          idToken = await cloudAuth.getIdToken();
        } catch (_) {
          idToken = null;
        }
      }

      await _pullOnce(
        backend: backend,
        sessionKey: sessionKey,
        config: config,
        managedVaultIdToken: idToken,
      );
      await _pushOnce(
        backend: backend,
        sessionKey: sessionKey,
        config: config,
        managedVaultIdToken: idToken,
      );

      if (mediaUploadsEnabled) {
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
      cloudAuth?.dispose();
    }
  }

  static Future<int> _pullOnce({
    required AppBackend backend,
    required Uint8List sessionKey,
    required SyncConfig config,
    required String? managedVaultIdToken,
  }) async {
    return switch (config.backendType) {
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
          if (idToken == null || idToken.trim().isEmpty) return 0;
          try {
            return await backend.syncManagedVaultPull(
              sessionKey,
              config.syncKey,
              baseUrl: config.baseUrl ?? '',
              vaultId: config.remoteRoot,
              idToken: idToken,
            );
          } catch (e) {
            final msg = e.toString();
            if (msg.contains('HTTP 402')) return 0;
            return 0;
          }
        }(),
    };
  }

  static Future<int> _pushOnce({
    required AppBackend backend,
    required Uint8List sessionKey,
    required SyncConfig config,
    required String? managedVaultIdToken,
  }) async {
    return switch (config.backendType) {
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
          if (idToken == null || idToken.trim().isEmpty) return 0;
          try {
            return await backend.syncManagedVaultPushOpsOnly(
              sessionKey,
              config.syncKey,
              baseUrl: config.baseUrl ?? '',
              vaultId: config.remoteRoot,
              idToken: idToken,
            );
          } catch (e) {
            final msg = e.toString();
            if (msg.contains('HTTP 402')) return 0;
            if (msg.contains('HTTP 403') && msg.contains('"grace_readonly"')) {
              return 0;
            }
            return 0;
          }
        }(),
    };
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
