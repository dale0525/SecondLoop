import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_update_models.dart';

AppUpdatePlatform detectAppUpdatePlatform() {
  if (kIsWeb) return AppUpdatePlatform.unsupported;
  if (Platform.isWindows) return AppUpdatePlatform.windows;
  if (Platform.isMacOS) return AppUpdatePlatform.macos;
  if (Platform.isLinux) return AppUpdatePlatform.linux;
  if (Platform.isAndroid) return AppUpdatePlatform.android;
  if (Platform.isIOS) return AppUpdatePlatform.ios;
  return AppUpdatePlatform.unsupported;
}

String currentArchitectureForUpdates() {
  try {
    return parseArchitectureHintFromPlatformVersion(Platform.version);
  } catch (_) {
    return 'unknown';
  }
}

String parseArchitectureHintFromPlatformVersion(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'unknown';
  }

  final onIndex = trimmed.lastIndexOf(' on "');
  if (onIndex >= 0) {
    final suffix = trimmed.substring(onIndex + 5).replaceAll('"', '').trim();
    if (suffix.isNotEmpty) {
      return suffix;
    }
  }

  return trimmed;
}
