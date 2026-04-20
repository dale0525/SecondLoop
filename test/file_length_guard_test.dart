import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review-target files stay below the 1000 line limit', () {
    const targets = <String>[
      'lib/core/sync/background_sync.dart',
      'test/sync_engine_gate_media_uploads_test.dart',
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
}
