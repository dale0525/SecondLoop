import 'package:shared_preferences/shared_preferences.dart';

abstract interface class WebPersistentAppDirResolver {
  Future<String> resolve({required String uid});

  Future<int> readGeneration({required String uid});

  Future<int> bumpGeneration({required String uid});
}

final class OpfsWebPersistentAppDirResolver
    implements WebPersistentAppDirResolver {
  OpfsWebPersistentAppDirResolver({
    Future<SharedPreferences> Function()? prefsProvider,
  }) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsProvider;

  static const _kGenerationKeyPrefix = 'web_native_app_dir_generation_v1:';

  @override
  Future<String> resolve({required String uid}) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('missing_web_uid');
    }
    final generation = await readGeneration(uid: normalizedUid);
    await ensureSecondLoopOpfsRoot();
    return '/opfs/secondloop/vaults/$normalizedUid/v$generation';
  }

  @override
  Future<int> readGeneration({required String uid}) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('missing_web_uid');
    }
    final prefs = await _prefsProvider();
    final stored = prefs.getInt(_generationKey(normalizedUid));
    return stored == null || stored < 0 ? 0 : stored;
  }

  @override
  Future<int> bumpGeneration({required String uid}) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('missing_web_uid');
    }
    final prefs = await _prefsProvider();
    final next = (prefs.getInt(_generationKey(normalizedUid)) ?? 0) + 1;
    await prefs.setInt(_generationKey(normalizedUid), next);
    return next;
  }

  static String _generationKey(String uid) => '$_kGenerationKeyPrefix$uid';
}

Future<void> ensureSecondLoopOpfsRoot() async {}
