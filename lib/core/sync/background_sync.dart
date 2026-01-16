import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
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
      hasSavedSessionKey: () async => (await backendForKey.loadSavedSessionKey()) != null,
      scheduler: sched,
    );

    await orchestrator.refreshSchedule();
  }

  static Future<bool> runOnce({required String taskName}) async {
    if (taskName != workmanagerTaskName) return true;

    final store = SyncConfigStore();
    final backend = NativeAppBackend();
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

    await backend.init();

    try {
      await _pullOnce(backend: backend, sessionKey: sessionKey, config: config);
      await _pushOnce(backend: backend, sessionKey: sessionKey, config: config);
      await rescheduleIfNeeded();
      return true;
    } catch (_) {
      await rescheduleIfNeeded();
      return false;
    }
  }

  static Future<int> _pullOnce({
    required AppBackend backend,
    required Uint8List sessionKey,
    required SyncConfig config,
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
    };
  }

  static Future<int> _pushOnce({
    required AppBackend backend,
    required Uint8List sessionKey,
    required SyncConfig config,
  }) async {
    return switch (config.backendType) {
      SyncBackendType.webdav => backend.syncWebdavPush(
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
    };
  }
}

final class WorkmanagerBackgroundSyncScheduler implements BackgroundSyncScheduler {
  @override
  Future<void> schedulePeriodicSync({required Duration frequency}) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await Workmanager().cancelByUniqueName(BackgroundSync.workmanagerUniqueName);
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
      await Workmanager().cancelByUniqueName(BackgroundSync.workmanagerUniqueName);
    } catch (_) {
      return;
    }
  }
}
