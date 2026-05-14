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
      RegExp(r'^lib/src/rust/api/external_import\.dart$'),
      RegExp(r'^lib/src/rust/api/migration_archive\.dart$'),
      RegExp(r'^rust/src/api/external_import\.rs$'),
      RegExp(r'^rust/src/api/migration_archive\.rs$'),
      RegExp(r'^test/(external_import|migration_archive)_.*\.dart$'),
      RegExp(r'^test/settings_(external_import|migration_archive)_.*\.dart$'),
      RegExp(r'^test/native_backend_external_import_recovery_test\.dart$'),
      RegExp(r'^rust/src/db/(external_import|migration_archive).*_tests\.rs$'),
      RegExp(r'^rust/tests/ask_ai_rag_includes_external_imports\.rs$'),
    ];
    final contentPattern = RegExp(
      r'ExternalImport|ExternalDocument|external_import|external readonly|external_readonly|external_document|'
      r'MigrationArchive|migrationArchive|migration_archive|'
      r'supportsExternalImport|supportsMigrationArchive',
    );
    final rustPublicLegacySurfacePattern = RegExp(
      r'pub\s+(?:const|fn|struct|enum|type|trait)\s+'
      r'(?:[A-Za-z0-9_]*external_(?:import|readonly|document)[A-Za-z0-9_]*|'
      r'[A-Za-z0-9_]*External(?:Import|Document)[A-Za-z0-9_]*|'
      r'[A-Za-z0-9_]*migration_archive[A-Za-z0-9_]*|'
      r'ExternalImport[A-Za-z0-9_]*|MigrationArchive[A-Za-z0-9_]*)',
    );
    final scannedContentPaths = <String>{
      'lib/core/backend/app_backend_semantic_and_sync.dart',
      'lib/core/backend/native_backend.dart',
      'lib/core/platform/app_platform_capabilities.dart',
      'lib/features/settings/settings_page.dart',
      'lib/features/settings/settings_page_build.dart',
      'lib/web_app/web_native_app_backend.dart',
      'rust/src/api/mod.rs',
      'test/agent_ui/agent_ui_acceptance_driver_test.dart',
      'integration_test/managed_pro_agent_ui_acceptance_test.dart',
    };

    for (final dirName in const [
      'lib',
      'test',
      'integration_test',
      'rust/src/api',
      'rust/src/db',
      'rust/tests',
    ]) {
      final dir = Directory('${root.path}/$dirName');
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart') && !entity.path.endsWith('.rs')) {
          continue;
        }

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
        final rustPublicLegacySurfaceMatches =
            relativePath.startsWith('rust/src/db/') &&
                rustPublicLegacySurfacePattern.hasMatch(source);
        if (pathMatches || contentMatches) {
          offenders.add(relativePath);
        } else if (rustPublicLegacySurfaceMatches) {
          offenders
              .add('$relativePath exposes public legacy import/archive API');
        }
      }
    }

    offenders.sort();
    expect(offenders, isEmpty);
  });
}

bool _isGenerated(String path) {
  return path.contains('/frb_generated') ||
      path.endsWith('/strings.g.dart') ||
      path.endsWith('/db.dart');
}
