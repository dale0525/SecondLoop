import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/macos/macos_update_client.dart';
import 'package:secondloop/core/update/update_event_log.dart';
import 'package:secondloop/core/update/windows/velopack_update_client.dart';

class InMemoryUpdateEventLogger implements UpdateEventLogger {
  final List<UpdateEventRecord> records = <UpdateEventRecord>[];

  @override
  Future<void> record(UpdateEventRecord record) async {
    records.add(record);
  }

  @override
  Future<List<UpdateEventRecord>> readRecent() async => records;
}

class ThrowingUpdateEventLogger implements UpdateEventLogger {
  ThrowingUpdateEventLogger({required this.failOnType});

  final UpdateEventType failOnType;
  final List<UpdateEventRecord> records = <UpdateEventRecord>[];

  @override
  Future<void> record(UpdateEventRecord record) async {
    if (record.type == failOnType) {
      throw StateError('logger_failed_${record.type.name}');
    }
    records.add(record);
  }

  @override
  Future<List<UpdateEventRecord>> readRecent() async => records;
}

class FakeWindowsStagedUpdateClient implements WindowsStagedUpdateClient {
  FakeWindowsStagedUpdateClient({
    required this.available,
    this.pendingUpdateAvailable = false,
    this.pendingUpdateVersionValue,
    this.pendingUpdatePackagePathValue,
    this.pendingApplyStartupResult =
        const PendingUpdateStartupResult.noPendingUpdate(),
    this.onStageAsset,
    this.onInstallAsset,
  });

  final bool available;
  final bool pendingUpdateAvailable;
  final String? pendingUpdateVersionValue;
  final String? pendingUpdatePackagePathValue;
  final PendingUpdateStartupResult pendingApplyStartupResult;
  final Future<void> Function(Uri assetDownloadUri)? onStageAsset;
  final Future<void> Function(Uri assetDownloadUri)? onInstallAsset;
  final List<Uri> stagedAssets = <Uri>[];
  final List<Uri> installedAssets = <Uri>[];
  int applyPendingCalls = 0;
  int applyPendingAndRestartCalls = 0;
  int installCalls = 0;
  int isAvailableCalls = 0;
  int? lastStartupWaitPid;

  @override
  bool isAvailable() {
    isAvailableCalls += 1;
    return available;
  }

  @override
  bool hasPendingUpdate() {
    return pendingUpdateAvailable;
  }

  @override
  String? pendingUpdateVersion() {
    return pendingUpdateAvailable ? pendingUpdateVersionValue : null;
  }

  @override
  String? pendingUpdatePackagePath() {
    return pendingUpdateAvailable ? pendingUpdatePackagePathValue : null;
  }

  @override
  Future<void> stageAsset(Uri assetDownloadUri) async {
    stagedAssets.add(assetDownloadUri);
    await onStageAsset?.call(assetDownloadUri);
  }

  @override
  Future<void> installAssetAndRestart(
    Uri assetDownloadUri, {
    required int waitPid,
  }) async {
    installCalls += 1;
    installedAssets.add(assetDownloadUri);
    await onInstallAsset?.call(assetDownloadUri);
  }

  @override
  Future<PendingUpdateStartupResult> applyPendingOnStartup({
    required int waitPid,
  }) async {
    applyPendingCalls += 1;
    lastStartupWaitPid = waitPid;
    return pendingApplyStartupResult;
  }

  @override
  Future<void> applyPendingAndRestart({required int waitPid}) async {
    applyPendingAndRestartCalls += 1;
  }
}

class FakeMacosManagedUpdateClient implements MacosManagedUpdateClient {
  FakeMacosManagedUpdateClient({
    required this.supportedInstallLocation,
    this.onInstallArchive,
  });

  final bool supportedInstallLocation;
  final Future<void> Function(Uri archiveUri)? onInstallArchive;
  final List<Uri> installedAssets = <Uri>[];
  int installCalls = 0;
  int isSupportedInstallLocationCalls = 0;

  @override
  bool isSupportedInstallLocation() {
    isSupportedInstallLocationCalls += 1;
    return supportedInstallLocation;
  }

  @override
  Future<void> installArchiveAndRestart(
    Uri archiveUri, {
    required int waitPid,
  }) async {
    installCalls += 1;
    installedAssets.add(archiveUri);
    await onInstallArchive?.call(archiveUri);
  }
}
