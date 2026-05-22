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
      expect(source, isNot(contains('AiSettingsPage')));
      expect(source, isNot(contains('AiAskAiSettingsPage')));
      expect(source, isNot(contains('settings_ai_source')));
      expect(source, isNot(contains('agent_settings_open_sync_settings')));
      expect(source, isNot(contains('openSyncSettings')));
      expect(source, isNot(contains('welcome_guide_card_ai')));
      expect(source, isNot(contains('welcome_guide_card_sync')));
      expect(source, isNot(contains('welcome_guide_card_sync_open')));
    }
  });

  test('runtime-first settings tree removes legacy AI and sync setting pages',
      () {
    for (final path in [
      'lib/features/settings/ai_settings_page.dart',
      'lib/features/settings/ai_settings_page_ui.dart',
      'lib/features/settings/ai_ask_ai_settings_page.dart',
      'lib/features/settings/ai_smart_organization_settings_page.dart',
      'lib/features/settings/llm_profiles_page.dart',
      'lib/features/settings/embedding_profiles_page.dart',
      'lib/features/settings/sync_settings_page.dart',
      'lib/features/settings/sync_settings_page_cloud_session.dart',
      'lib/features/settings/sync_settings_page_delete_actions.dart',
      'lib/features/settings/sync_settings_page_delete_progress.dart',
      'lib/features/settings/sync_settings_page_managed_vault_save.dart',
      'lib/features/settings/sync_settings_page_managed_vault_sync.dart',
      'lib/features/settings/sync_settings_page_media_actions.dart',
      'lib/features/settings/sync_settings_page_switch_direction.dart',
      'lib/features/settings/sync_settings_page_sync_actions.dart',
      'lib/features/settings/sync_settings_page_sync_progress.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: '$path is retired');
    }
  });

  test('sync engine gate no longer starts local-first sync engine', () {
    final source =
        File('lib/core/sync/sync_engine_gate.dart').readAsStringSync();

    expect(source, isNot(contains('SyncEngine(')));
    expect(source, isNot(contains('syncWebdavPush')));
    expect(source, isNot(contains('syncLocaldirPush')));
  });

  test('app shell does not mount local attachment or media processing gates',
      () {
    final source = File('lib/app/app.dart').readAsStringSync();

    for (final token in [
      'MediaEnrichmentGate',
      'ShareIngestGate',
      'ShareIntentListener',
      'media_enrichment_gate.dart',
      'share_ingest_gate.dart',
      'share_intent_listener.dart',
    ]) {
      expect(
        source,
        isNot(contains(token)),
        reason: 'normal app shell must not mount $token',
      );
    }
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
