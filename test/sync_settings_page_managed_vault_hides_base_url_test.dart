import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Managed vault does not show base URL field by default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: Scaffold(
            body: SyncSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Managed Vault base URL',
      ),
      findsNothing,
    );
  });
}
