import 'dart:typed_data';

import '../backend/app_backend.dart';
import '../../src/rust/db.dart';

Future<bool> hasActiveLlmProfile(
  AppBackend backend,
  Uint8List sessionKey,
) async {
  final profiles = await backend.listLlmProfiles(sessionKey);
  return profiles.any((p) => p.isActive);
}

