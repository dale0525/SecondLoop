enum AppUpdatePlatform {
  windows,
  macos,
  linux,
  android,
  ios,
  unsupported,
}

enum AppUpdateInstallMode {
  seamlessRestart,
  stagedNextLaunch,
  externalDownload,
}

class AppRuntimeVersion {
  const AppRuntimeVersion({
    required this.version,
    required this.buildNumber,
  });

  final String version;
  final String buildNumber;

  String get display {
    final cleanBuild = buildNumber.trim();
    if (cleanBuild.isEmpty) return version;
    return '$version+$cleanBuild';
  }
}

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.downloadUri,
    this.sha256,
  });

  final String name;
  final Uri downloadUri;
  final String? sha256;
}

class AppUpdateAvailability {
  const AppUpdateAvailability({
    required this.currentVersion,
    required this.latestTag,
    required this.releasePageUri,
    required this.installMode,
    this.asset,
  });

  final String currentVersion;
  final String latestTag;
  final Uri releasePageUri;
  final AppUpdateInstallMode installMode;
  final AppUpdateAsset? asset;

  Uri get downloadUri => asset?.downloadUri ?? releasePageUri;
  bool get canSeamlessInstall =>
      installMode == AppUpdateInstallMode.seamlessRestart;
  bool get canStageForNextLaunch =>
      installMode == AppUpdateInstallMode.stagedNextLaunch;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    this.update,
    this.errorMessage,
  });

  final String currentVersion;
  final AppUpdateAvailability? update;
  final String? errorMessage;

  bool get isUpToDate => update == null && errorMessage == null;
}

enum PendingUpdateStartupStatus {
  none,
  dispatched,
  inProgress,
}

class PendingUpdateStartupResult {
  const PendingUpdateStartupResult._({required this.status});

  const PendingUpdateStartupResult.noPendingUpdate()
      : this._(status: PendingUpdateStartupStatus.none);

  const PendingUpdateStartupResult.updateDispatched()
      : this._(status: PendingUpdateStartupStatus.dispatched);

  const PendingUpdateStartupResult.updateInProgress()
      : this._(status: PendingUpdateStartupStatus.inProgress);

  final PendingUpdateStartupStatus status;

  bool get hasNoPendingUpdate => status == PendingUpdateStartupStatus.none;
  bool get didLaunchUpdater => status == PendingUpdateStartupStatus.dispatched;
  bool get isUpdateInProgress =>
      status == PendingUpdateStartupStatus.inProgress;
  bool get shouldTerminateStartup =>
      status == PendingUpdateStartupStatus.dispatched ||
      status == PendingUpdateStartupStatus.inProgress;
}

int compareReleaseTagWithCurrentVersion(
    String releaseTag, String currentVersion) {
  final releaseSegments = tryParseStrictAppVersion(releaseTag);
  final currentSegments = tryParseStrictAppVersion(currentVersion);
  if (releaseSegments == null || currentSegments == null) return 0;

  for (var i = 0; i < 3; i++) {
    if (releaseSegments[i] != currentSegments[i]) {
      return releaseSegments[i].compareTo(currentSegments[i]);
    }
  }

  return 0;
}

bool isStrictAppVersion(String input) {
  return tryParseStrictAppVersion(input) != null;
}

List<int>? tryParseStrictAppVersion(String input) {
  final match = RegExp(r'^[vV]?(\d+)\.(\d+)\.(\d+)$').firstMatch(input.trim());
  if (match == null) {
    return null;
  }

  final major = int.tryParse(match.group(1) ?? '');
  final minor = int.tryParse(match.group(2) ?? '');
  final patch = int.tryParse(match.group(3) ?? '');
  if (major == null || minor == null || patch == null) {
    return null;
  }

  return <int>[major, minor, patch];
}
