import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/secure_blob_store.dart';

@immutable
class CloudAuthStoredSession {
  const CloudAuthStoredSession({required this.uid, required this.refreshToken});

  final String uid;
  final String refreshToken;
}

abstract class CloudAuthStore {
  Future<CloudAuthStoredSession?> load();
  Future<void> save(CloudAuthStoredSession session);
  Future<void> clear();
}

typedef CloudAuthPrefsProvider = Future<SharedPreferences> Function();

CloudAuthStore createDefaultCloudAuthStore() {
  final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  if (isMac) return PrefsCloudAuthStore();
  return SecureCloudAuthStore();
}

final class SecureCloudAuthStore implements CloudAuthStore {
  SecureCloudAuthStore({SecureBlobStore? secureStore})
      : _secureStore = secureStore ?? SecureBlobStore();

  final SecureBlobStore _secureStore;

  static const _kUid = 'cloud_uid';
  static const _kRefreshToken = 'cloud_refresh_token';

  @override
  Future<CloudAuthStoredSession?> load() async {
    final all = await _secureStore.readAll();
    final uid = all[_kUid];
    final refreshToken = all[_kRefreshToken];

    if (uid == null || uid.trim().isEmpty) return null;
    if (refreshToken == null || refreshToken.trim().isEmpty) return null;

    return CloudAuthStoredSession(uid: uid, refreshToken: refreshToken);
  }

  @override
  Future<void> save(CloudAuthStoredSession session) async {
    await _secureStore.update({
      _kUid: session.uid,
      _kRefreshToken: session.refreshToken,
    });
  }

  @override
  Future<void> clear() async {
    await _secureStore.update({
      _kUid: null,
      _kRefreshToken: null,
    });
  }
}

final class PrefsCloudAuthStore implements CloudAuthStore {
  PrefsCloudAuthStore({CloudAuthPrefsProvider? prefsProvider})
      : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final CloudAuthPrefsProvider _prefsProvider;

  static const _kUidPrefs = 'cloud_uid_v1';
  static const _kRefreshTokenPrefs = 'cloud_refresh_token_v1';

  @override
  Future<CloudAuthStoredSession?> load() async {
    final prefs = await _prefsProvider();
    final uid = prefs.getString(_kUidPrefs);
    final refreshToken = prefs.getString(_kRefreshTokenPrefs);
    if (uid == null || uid.trim().isEmpty) return null;
    if (refreshToken == null || refreshToken.trim().isEmpty) return null;
    return CloudAuthStoredSession(uid: uid, refreshToken: refreshToken);
  }

  @override
  Future<void> save(CloudAuthStoredSession session) async {
    final prefs = await _prefsProvider();
    await prefs.setString(_kUidPrefs, session.uid);
    await prefs.setString(_kRefreshTokenPrefs, session.refreshToken);
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefsProvider();
    await prefs.remove(_kUidPrefs);
    await prefs.remove(_kRefreshTokenPrefs);
  }
}
