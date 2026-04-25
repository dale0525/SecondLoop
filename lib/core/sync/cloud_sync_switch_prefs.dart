import 'package:shared_preferences/shared_preferences.dart';

const cloudSyncSwitchInProgressPrefsKey = 'cloud_sync_switch_in_progress_v1';
const cloudSyncSwitchStartedAtPrefsKey = 'cloud_sync_switch_started_at_ms_v1';
const kCloudSyncSwitchLeaseDuration = Duration(minutes: 30);

Future<void> markCloudSyncSwitchInProgress({DateTime? now}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(
    cloudSyncSwitchStartedAtPrefsKey,
    (now ?? DateTime.now()).millisecondsSinceEpoch,
  );
  await prefs.setBool(cloudSyncSwitchInProgressPrefsKey, true);
}

Future<void> clearCloudSyncSwitchInProgress() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(cloudSyncSwitchInProgressPrefsKey, false);
  await prefs.remove(cloudSyncSwitchStartedAtPrefsKey);
}

Future<bool> cloudSyncSwitchInProgress({DateTime? now}) async {
  final prefs = await SharedPreferences.getInstance();
  final marked = prefs.getBool(cloudSyncSwitchInProgressPrefsKey) ?? false;
  if (!marked) {
    await prefs.remove(cloudSyncSwitchStartedAtPrefsKey);
    return false;
  }

  final startedAtMs = prefs.getInt(cloudSyncSwitchStartedAtPrefsKey);
  if (startedAtMs == null || startedAtMs <= 0) {
    await clearCloudSyncSwitchInProgress();
    return false;
  }

  final elapsed = (now ?? DateTime.now()).millisecondsSinceEpoch - startedAtMs;
  final leaseMs = kCloudSyncSwitchLeaseDuration.inMilliseconds;
  if (elapsed > leaseMs || elapsed < -leaseMs) {
    await clearCloudSyncSwitchInProgress();
    return false;
  }

  return true;
}
