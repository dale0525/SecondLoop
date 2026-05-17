Future<OplogMaintenanceStats> dbRunOplogMaintenance(
        {required String appDir,
        required List<int> key,
        required OplogMaintenanceBackend backend,
        required String scopeId}) =>
    throw UnsupportedError('rust_runtime_removed:dbRunOplogMaintenance');

enum OplogMaintenanceBackend {
  webDav,
  localDir,
  managedVault,
  ;
}

class OplogMaintenanceStats {
  final BigInt beforeCount;
  final BigInt afterCount;
  final BigInt prunedCount;

  const OplogMaintenanceStats({
    required this.beforeCount,
    required this.afterCount,
    required this.prunedCount,
  });

  @override
  int get hashCode =>
      beforeCount.hashCode ^ afterCount.hashCode ^ prunedCount.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OplogMaintenanceStats &&
          runtimeType == other.runtimeType &&
          beforeCount == other.beforeCount &&
          afterCount == other.afterCount &&
          prunedCount == other.prunedCount;
}
