import 'package:flutter/foundation.dart';

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
