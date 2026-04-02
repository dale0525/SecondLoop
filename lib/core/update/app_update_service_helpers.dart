part of 'app_update_service.dart';

String? _normalizeLatestTag(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final normalized = trimmed.startsWith('v') ? trimmed : 'v$trimmed';
  if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

String? _readString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

Uri? _parseUri(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || (!uri.hasScheme && !uri.hasAuthority)) return null;
  return uri;
}

extension AppUpdateServiceHelperMethods on AppUpdateService {
  Future<void> _recordEvent(
    UpdateEventType type, {
    String? currentVersion,
    String? latestTag,
    AppUpdateInstallMode? installMode,
    String? message,
  }) async {
    try {
      await _updateEventLogger.record(
        UpdateEventRecord(
          type: type,
          timestampUtc: DateTime.now().toUtc(),
          platform: _platform,
          currentVersion: currentVersion,
          latestTag: latestTag,
          installMode: installMode,
          message: message,
        ),
      );
    } catch (_) {}
  }

  Future<void> _recordFailure(
    UpdateEventType type,
    Object error, {
    String? currentVersion,
    String? latestTag,
    AppUpdateInstallMode? installMode,
  }) async {
    try {
      await _updateEventLogger.record(
        UpdateEventRecord(
          type: type,
          timestampUtc: DateTime.now().toUtc(),
          platform: _platform,
          currentVersion: currentVersion,
          latestTag: latestTag,
          installMode: installMode,
          message: error.toString(),
          failureCategory: classifyUpdateFailure(error),
        ),
      );
    } catch (_) {}
  }

  String _describeManualFallbackReason(AppUpdateAsset? asset) {
    if (asset == null) {
      return 'missing_platform_asset';
    }
    if (_platform == AppUpdatePlatform.windows &&
        _isWindowsVelopackPackageName(asset.name)) {
      return 'windows_runtime_unavailable';
    }
    if (_platform == AppUpdatePlatform.macos &&
        _isMacosManagedArchiveName(asset.name)) {
      return 'macos_install_location_unsupported_or_integrity_missing';
    }
    return 'manual_download_required';
  }

  bool _isAndroidApkInstallerCandidate(AppUpdateAsset? asset) {
    return _platform == AppUpdatePlatform.android &&
        asset != null &&
        isAndroidApkAssetForUpdate(asset);
  }

  bool _isAndroidManualFallbackPlatformKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized == 'android' ||
        normalized == 'android-universal' ||
        normalized == 'android-arm64-v8a' ||
        normalized == 'android-arm64' ||
        normalized == 'android-armeabi-v7a' ||
        normalized == 'android-armv7' ||
        normalized == 'android-arm-v7a';
  }

  bool _isAndroidManualFallbackAssetCandidate(AppUpdateAsset asset) {
    if (!_isAndroidApkAssetImpl(asset)) {
      return false;
    }

    if (extractLeadingAndroidAbi(asset.name) != null) {
      return true;
    }

    return isUniversalAndroidApkName(asset.name);
  }
}
