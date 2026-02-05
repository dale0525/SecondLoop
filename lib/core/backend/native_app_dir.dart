import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

String? _cachedAppDir;

Future<String> getNativeAppDir() async {
  if (kIsWeb) {
    throw StateError('native_app_dir_not_available_on_web');
  }

  final cached = _cachedAppDir;
  if (cached != null) return cached;

  final dir = await getApplicationSupportDirectory();
  _cachedAppDir = dir.path;
  return _cachedAppDir!;
}
