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
    return Platform.version;
  } catch (_) {
    return 'unknown';
  }
}
