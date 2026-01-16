import 'sync_engine.dart';

abstract class BackgroundSyncScheduler {
  Future<void> schedulePeriodicSync({required Duration frequency});
  Future<void> cancelPeriodicSync();
}

final class BackgroundSyncOrchestrator {
  BackgroundSyncOrchestrator({
    required this.readAutoEnabled,
    required this.loadConfig,
    required this.hasSavedSessionKey,
    required this.scheduler,
    this.frequency = const Duration(minutes: 15),
  });

  final Future<bool> Function() readAutoEnabled;
  final Future<SyncConfig?> Function() loadConfig;
  final Future<bool> Function() hasSavedSessionKey;

  final BackgroundSyncScheduler scheduler;
  final Duration frequency;

  Future<void> refreshSchedule() async {
    final enabled = await readAutoEnabled();
    if (!enabled) {
      await scheduler.cancelPeriodicSync();
      return;
    }

    final config = await loadConfig();
    if (config == null) {
      await scheduler.cancelPeriodicSync();
      return;
    }

    final hasKey = await hasSavedSessionKey();
    if (!hasKey) {
      await scheduler.cancelPeriodicSync();
      return;
    }

    await scheduler.schedulePeriodicSync(frequency: frequency);
  }
}

