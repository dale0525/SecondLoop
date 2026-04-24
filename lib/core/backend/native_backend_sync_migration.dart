part of 'native_backend.dart';

mixin _NativeAppBackendSyncMigration on _NativeAppBackendAccess {
  @override
  Future<MigrationArchiveExportEstimate> estimateMigrationArchiveExport(
    Uint8List key,
  ) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveExportEstimate(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<MigrationArchiveManifest> exportMigrationArchive(
    Uint8List key, {
    required String outputPath,
  }) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveExport(
      appDir: appDir,
      key: key,
      outputPath: outputPath,
    );
  }

  @override
  Stream<String> runMigrationArchiveExportProgress(
    Uint8List key, {
    required String outputPath,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_migration_archive.migrationArchiveExportProgress(
      appDir: appDir,
      key: key,
      outputPath: outputPath,
    );
  }

  @override
  Future<MigrationArchiveManifest> inspectMigrationArchive({
    required String archivePath,
  }) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveInspect(
      appDir: appDir,
      archivePath: archivePath,
    );
  }

  @override
  Future<MigrationArchiveManifest> importMigrationArchive(
    Uint8List key, {
    required String archivePath,
  }) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveImport(
      appDir: appDir,
      key: key,
      archivePath: archivePath,
    );
  }

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveCreateRollbackSnapshot(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) async {
    final appDir = await _getAppDir();
    await rust_migration_archive.migrationArchiveRestoreRollbackSnapshot(
      appDir: appDir,
      key: key,
      snapshotPath: snapshotPath,
    );
  }

  @override
  Future<void> deleteVaultRollbackSnapshot(
      {required String snapshotPath}) async {
    await rust_migration_archive.migrationArchiveRemoveRollbackSnapshot(
      snapshotPath: snapshotPath,
    );
  }

  @override
  Stream<String> runMigrationArchiveImportProgress(
    Uint8List key, {
    required String archivePath,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_migration_archive.migrationArchiveImportProgress(
      appDir: appDir,
      key: key,
      archivePath: archivePath,
    );
  }

  @override
  Future<ExternalImportScanSummary> scanExternalImportSource({
    required String sourcePath,
  }) async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportScanSource(
      appDir: appDir,
      sourcePath: sourcePath,
    );
  }

  @override
  Future<List<ExternalImportBatchSummary>> listExternalImportBatches() async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportListBatches(
      appDir: appDir,
    );
  }

  @override
  Future<String> readExternalImportBatchReport({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportBatchReportJson(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Stream<String> runExternalImportProgress(
    Uint8List key, {
    required String sourcePath,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_external_import.externalImportRunProgress(
      appDir: appDir,
      key: key,
      sourcePath: sourcePath,
    );
  }

  @override
  Future<void> deleteExternalImportBatch({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    await rust_external_import.externalImportDeleteBatch(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Future<void> requestExternalImportCancel({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    await rust_external_import.externalImportRequestCancel(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Future<String> estimateExternalImportPhaseB({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportPhaseBEstimateJson(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Future<String> readExternalImportPhaseBState({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportPhaseBStateJson(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Stream<String> runExternalImportPhaseBProgress(
    Uint8List key, {
    required String batchId,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_external_import.externalImportPhaseBRunProgress(
      appDir: appDir,
      key: key,
      batchId: batchId,
    );
  }
}
