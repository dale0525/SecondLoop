import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review-target files stay below the 1000 line limit', () {
    const targets = <String>[
      'lib/core/backend/native_backend.dart',
      'lib/core/sync/cloud_sync_switch_prompt_gate.dart',
      'lib/core/sync/background_sync.dart',
      'lib/i18n/settings_en.i18n.json',
      'lib/i18n/settings_zh_CN.i18n.json',
      'test/sync_engine_gate_media_uploads_test.dart',
      'test/sync_settings_page_test_support_part.dart',
      'test/sync_settings_page_managed_vault_support_part.dart',
      'rust/tests/sync_managed_vault_v2_pull.rs',
      'rust/tests/sync_managed_vault_v2_push.rs',
    ];

    for (final path in targets) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'Missing $path');
      final lineCount = file.readAsLinesSync().length;
      expect(
        lineCount,
        lessThan(1000),
        reason: '$path should stay below 1000 lines, got $lineCount',
      );
    }
  });

  test(
      'native_backend keeps cloud media backup implementations in split part files',
      () {
    final content =
        File('lib/core/backend/native_backend.dart').readAsStringSync();
    const disallowedImplementations = <String>[
      'Future<void> enqueueCloudMediaBackup(',
      'Future<int> backfillCloudMediaBackupImages(',
      'Future<List<CloudMediaBackup>> listDueCloudMediaBackups(',
      'Future<void> markCloudMediaBackupFailed(',
      'Future<void> markCloudMediaBackupUploaded(',
      'Future<CloudMediaBackupSummary> cloudMediaBackupSummary(',
    ];

    for (final signature in disallowedImplementations) {
      expect(
        content.contains(signature),
        isFalse,
        reason:
            'native_backend.dart should not keep duplicate implementation: $signature',
      );
    }
  });
}
