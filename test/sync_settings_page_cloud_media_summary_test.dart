import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('managed vault sync settings shows zero media upload stats',
      (tester) async {
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('en'),
          home: AppBackendScope(
            backend: _SummaryBackend(
              const CloudMediaBackupSummary(
                pending: 0,
                failed: 0,
                uploaded: 0,
              ),
            ),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('sync_media_backup_enabled')),
    );

    expect(find.text('Queued 0 · Failed 0 · Uploaded 0'), findsOneWidget);
    expect(find.textContaining('missing_local_attachment_bytes'), findsNothing);
  });
}

Future<void> _ensureVisible(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  try {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: scrollable,
    );
  } catch (_) {
    await tester.scrollUntilVisible(
      target,
      -180,
      scrollable: scrollable,
    );
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final class _SummaryBackend extends AppBackend {
  _SummaryBackend(this.summary);

  final CloudMediaBackupSummary summary;

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(Uint8List key) async {
    return summary;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
