import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy public local import and migration archive surfaces are removed',
      () {
    final root = Directory.current;
    final offenders = <String>[];

    final pathPatterns = <RegExp>[
      RegExp(r'^lib/features/settings/external_import[^/]*\.dart$'),
      RegExp(r'^lib/features/settings/migration_archive_page\.dart$'),
      RegExp(r'^test/(external_import|migration_archive)_.*\.dart$'),
      RegExp(r'^test/settings_(external_import|migration_archive)_.*\.dart$'),
      RegExp(r'^test/native_backend_external_import_recovery_test\.dart$'),
    ];
    final contentPattern = RegExp(
      r'ExternalImport|ExternalDocument|external_import|external readonly|external_readonly|external_document|'
      r'MigrationArchive|migrationArchive|migration_archive|'
      r'supportsExternalImport|supportsMigrationArchive',
    );
    final scannedContentPaths = <String>{
      'lib/core/backend/app_backend_semantic_and_sync.dart',
      'lib/core/backend/native_backend.dart',
      'lib/core/platform/app_platform_capabilities.dart',
      'lib/features/settings/settings_page.dart',
      'lib/features/settings/settings_page_build.dart',
      'lib/web_app/web_native_app_backend.dart',
      'test/agent_ui/agent_ui_acceptance_driver_test.dart',
      'integration_test/managed_pro_agent_ui_acceptance_test.dart',
    };

    for (final dirName in const [
      'lib',
      'test',
      'integration_test',
    ]) {
      final dir = Directory('${root.path}/$dirName');
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final relativePath = entity.path.replaceFirst('${root.path}/', '');
        if (_isGenerated(relativePath) ||
            relativePath.endsWith('legacy_local_import_removal_test.dart')) {
          continue;
        }

        final pathMatches =
            pathPatterns.any((pattern) => pattern.hasMatch(relativePath));
        final source = entity.readAsStringSync();
        final contentMatches = scannedContentPaths.contains(relativePath) &&
            contentPattern.hasMatch(source);
        if (pathMatches || contentMatches) {
          offenders.add(relativePath);
        }
      }
    }

    offenders.sort();
    expect(offenders, isEmpty);
  });
}

bool _isGenerated(String path) {
  return path.endsWith('/strings.g.dart') || path.endsWith('/db.dart');
}
