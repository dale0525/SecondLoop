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
    this.installModeHint,
  });

  final String name;
  final Uri downloadUri;
  final String? sha256;
  final AppUpdateInstallMode? installModeHint;
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
  final releaseVersion = parseComparableAppVersion(releaseTag);
  final currentAppVersion = parseComparableAppVersion(currentVersion);
  if (releaseVersion == null || currentAppVersion == null) return 0;

  final normalizedRelease = trimTrailingZeroSegments(releaseVersion.segments);
  final normalizedCurrent =
      trimTrailingZeroSegments(currentAppVersion.segments);
  final comparedLength = normalizedRelease.length > normalizedCurrent.length
      ? normalizedRelease.length
      : normalizedCurrent.length;

  for (var i = 0; i < comparedLength; i += 1) {
    final releaseValue =
        i < normalizedRelease.length ? normalizedRelease[i] : 0;
    final currentValue =
        i < normalizedCurrent.length ? normalizedCurrent[i] : 0;
    if (releaseValue != currentValue) {
      return releaseValue.compareTo(currentValue);
    }
  }

  if (releaseVersion.isPrerelease != currentAppVersion.isPrerelease) {
    return releaseVersion.isPrerelease ? -1 : 1;
  }

  if (releaseVersion.isPrerelease) {
    return comparePrereleaseIdentifiers(
      releaseVersion.prereleaseIdentifiers,
      currentAppVersion.prereleaseIdentifiers,
    );
  }

  return 0;
}

bool isStrictAppVersion(String input) {
  return tryParseStrictAppVersion(input) != null;
}

ComparableAppVersion? parseComparableAppVersion(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final match = RegExp(
    r'^[vV]?(\d+(?:\.\d+){2,7})(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  ).firstMatch(trimmed);
  if (match == null) {
    return null;
  }

  final segments = <int>[];
  for (final value in (match.group(1) ?? '').split('.')) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      return null;
    }
    segments.add(parsed);
  }

  if (segments.isEmpty) {
    return null;
  }

  final prerelease = match.group(2)?.trim();
  final prereleaseSegments = <int>[];
  final prereleaseIdentifiers = <ComparablePrereleaseIdentifier>[];
  if (prerelease != null && prerelease.isNotEmpty) {
    for (final value in prerelease.split('.')) {
      final trimmedValue = value.trim();
      if (trimmedValue.isEmpty) {
        return null;
      }
      final parsed = int.tryParse(value);
      if (parsed != null) {
        prereleaseSegments.add(parsed);
        prereleaseIdentifiers.add(
          ComparablePrereleaseIdentifier.numeric(parsed),
        );
      } else {
        prereleaseIdentifiers.add(
          ComparablePrereleaseIdentifier.alpha(trimmedValue.toLowerCase()),
        );
      }
    }
  }

  return ComparableAppVersion(
    segments: segments,
    prereleaseSegments: prereleaseSegments,
    prereleaseIdentifiers: prereleaseIdentifiers,
    isPrerelease: prerelease != null && prerelease.isNotEmpty,
  );
}

int comparePrereleaseIdentifiers(
  List<ComparablePrereleaseIdentifier> left,
  List<ComparablePrereleaseIdentifier> right,
) {
  final comparedLength =
      left.length > right.length ? left.length : right.length;
  for (var i = 0; i < comparedLength; i += 1) {
    if (i >= left.length) {
      return -1;
    }
    if (i >= right.length) {
      return 1;
    }
    final compared = left[i].compareTo(right[i]);
    if (compared != 0) {
      return compared;
    }
  }
  return 0;
}

List<int> trimTrailingZeroSegments(List<int> segments) {
  final normalized = List<int>.from(segments, growable: true);
  while (normalized.length > 1 && normalized.last == 0) {
    normalized.removeLast();
  }
  return normalized;
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

class ComparableAppVersion {
  const ComparableAppVersion({
    required this.segments,
    required this.prereleaseSegments,
    required this.prereleaseIdentifiers,
    required this.isPrerelease,
  });

  final List<int> segments;
  final List<int> prereleaseSegments;
  final List<ComparablePrereleaseIdentifier> prereleaseIdentifiers;
  final bool isPrerelease;

  bool get hasNumericPrereleaseSegments => prereleaseSegments.isNotEmpty;
}

class ComparablePrereleaseIdentifier {
  const ComparablePrereleaseIdentifier._({
    required this.value,
    required this.numericValue,
    required this.isNumeric,
  });

  const ComparablePrereleaseIdentifier.numeric(int value)
      : this._(value: '$value', numericValue: value, isNumeric: true);

  const ComparablePrereleaseIdentifier.alpha(String value)
      : this._(value: value, numericValue: null, isNumeric: false);

  final String value;
  final int? numericValue;
  final bool isNumeric;

  int compareTo(ComparablePrereleaseIdentifier other) {
    if (isNumeric && other.isNumeric) {
      return numericValue!.compareTo(other.numericValue!);
    }
    if (isNumeric != other.isNumeric) {
      return isNumeric ? -1 : 1;
    }
    return value.compareTo(other.value);
  }
}
