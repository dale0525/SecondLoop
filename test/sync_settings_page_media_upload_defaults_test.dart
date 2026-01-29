import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Media uploads default to on + Wi‑Fi only (webdav)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: TestAppBackend(),
            child: Scaffold(body: SyncSettingsPage(configStore: store)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    final enabled = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('sync_media_backup_enabled')),
    );
    expect(enabled.value, isTrue);

    final wifiOnly = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('sync_media_backup_wifi_only')),
    );
    expect(wifiOnly.value, isTrue);
    expect(wifiOnly.onChanged, isNotNull);
  });
}
