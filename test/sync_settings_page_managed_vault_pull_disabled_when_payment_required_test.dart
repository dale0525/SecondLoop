import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Managed vault disables Pull when payment is required',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');

    final engine = SyncEngine(
      syncRunner: _NoopRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
    );
    engine.writeGate.value = const SyncWriteGateState.paymentRequired();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SyncEngineScope(
            engine: engine,
            child: Scaffold(
              body: SyncSettingsPage(configStore: store),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final pull = find.widgetWithText(OutlinedButton, 'Pull');
    expect(pull, findsOneWidget);
    expect(tester.widget<OutlinedButton>(pull).onPressed, isNull);
  });
}

final class _NoopRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}
