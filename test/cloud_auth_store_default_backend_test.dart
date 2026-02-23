import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/cloud/cloud_auth_store.dart';

void main() {
  test('createDefaultCloudAuthStore: macOS uses shared preferences store', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final store = createDefaultCloudAuthStore();
      expect(store, isA<PrefsCloudAuthStore>());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('createDefaultCloudAuthStore: Windows uses secure store', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final store = createDefaultCloudAuthStore();
      expect(store, isA<SecureCloudAuthStore>());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('PrefsCloudAuthStore save/load/clear roundtrip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsCloudAuthStore();

    expect(await store.load(), isNull);

    const saved = CloudAuthStoredSession(uid: 'uid_1', refreshToken: 'rt_1');
    await store.save(saved);

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.uid, 'uid_1');
    expect(loaded.refreshToken, 'rt_1');

    await store.clear();
    expect(await store.load(), isNull);
  });
}
