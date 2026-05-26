import 'runtime_connection_store.dart';
import 'runtime_profile.dart';

Future<CloudRuntimeConnection?> loadRuntimeConnectionSafely() async {
  try {
    return await RuntimeConnectionStore().loadConnection();
  } catch (_) {
    return RuntimeConnectionStore.cachedConnection;
  }
}

CloudRuntimeConnection? selfManagedRuntimeConnection(
  CloudRuntimeConnection? connection,
) {
  return connection?.profile.runtimeMode == CloudRuntimeMode.selfManaged
      ? connection
      : null;
}

CloudRuntimeConnection? cachedSelfManagedRuntimeConnection() {
  return selfManagedRuntimeConnection(RuntimeConnectionStore.cachedConnection);
}
