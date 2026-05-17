import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/settings/cloud_runtime_mode_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('runtime mode exposes only managed pro and self-managed',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(home: CloudRuntimeModePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('runtime_mode_managed_pro')), findsOneWidget);
    expect(find.byKey(const ValueKey('runtime_mode_self_managed')),
        findsOneWidget);
    expect(find.textContaining('WebDAV'), findsNothing);
    expect(find.textContaining('Folder'), findsNothing);
    expect(find.textContaining('Local directory'), findsNothing);
  });

  test('runtime-first settings do not link to legacy sync settings', () {
    final settingsBuild = File(
      'lib/features/settings/settings_page_build.dart',
    ).readAsStringSync();
    final agentSettings = File(
      'lib/features/settings/agent_settings_page.dart',
    ).readAsStringSync();
    final welcome =
        File('lib/features/welcome/welcome_page.dart').readAsStringSync();
    final dynamicHarness = File(
      'integration_test/support/dynamic_app_harness.dart',
    ).readAsStringSync();

    for (final source in [
      settingsBuild,
      agentSettings,
      welcome,
      dynamicHarness
    ]) {
      expect(source, isNot(contains('SyncSettingsPage')));
      expect(source, isNot(contains('settings_sync')));
      expect(source, isNot(contains('agent_settings_open_sync_settings')));
      expect(source, isNot(contains('openSyncSettings')));
      expect(source, isNot(contains('welcome_guide_card_sync_open')));
    }
  });

  test('sync engine gate no longer starts local-first sync engine', () {
    final source =
        File('lib/core/sync/sync_engine_gate.dart').readAsStringSync();

    expect(source, isNot(contains('SyncEngine(')));
    expect(source, isNot(contains('syncWebdavPush')));
    expect(source, isNot(contains('syncLocaldirPush')));
  });

  test('chat notes and attachment storage do not instantiate SyncEngine', () {
    final files = [
      ...Directory('lib/features/chat')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/features/notes')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      File('lib/features/attachments/attachment_storage_controller.dart'),
      File('lib/features/settings/vault_usage_card.dart'),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('SyncEngine(')),
        reason: file.path,
      );
    }
  });
}
