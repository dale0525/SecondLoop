part of 'background_sync.dart';

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
