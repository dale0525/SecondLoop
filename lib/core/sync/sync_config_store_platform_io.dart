import 'dart:io';

import 'package:flutter/foundation.dart';

bool syncConfigStoreIsFlutterTestEnvironment() {
  return Platform.environment.containsKey('FLUTTER_TEST');
}

bool syncConfigStoreIsMacPlatform() {
  return Platform.isMacOS || defaultTargetPlatform == TargetPlatform.macOS;
}
