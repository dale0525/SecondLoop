import 'dart:math';

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
  final releaseSegments = _parseVersionSegments(releaseTag);
  final currentSegments = _parseVersionSegments(currentVersion);
  if (releaseSegments.isEmpty || currentSegments.isEmpty) return 0;

  final comparedLength = max(
    min(3, releaseSegments.length),
    min(3, currentSegments.length),
  );

  for (var i = 0; i < comparedLength; i++) {
    final releaseValue = i < releaseSegments.length ? releaseSegments[i] : 0;
    final currentValue = i < currentSegments.length ? currentSegments[i] : 0;
    if (releaseValue != currentValue) {
      return releaseValue.compareTo(currentValue);
    }
  }

  return 0;
}

List<int> _parseVersionSegments(String input) {
  final matches = RegExp(r'\d+').allMatches(input.trim());
  if (matches.isEmpty) {
    return const [];
  }

  final segments = <int>[];
  for (final match in matches) {
    final parsed = int.tryParse(match.group(0) ?? '');
    if (parsed == null) continue;
    segments.add(parsed);
    if (segments.length >= 8) {
      break;
    }
  }
  return segments;
}
