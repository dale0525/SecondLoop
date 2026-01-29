import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';

void main() {
  test('Cloud media uploads default to enabled + Wi‑Fi only', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();

    expect(await store.readCloudMediaBackupEnabled(), isTrue);
    expect(await store.readCloudMediaBackupWifiOnly(), isTrue);
  });
}
