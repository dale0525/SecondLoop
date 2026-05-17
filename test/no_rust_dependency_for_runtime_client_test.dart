import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime-first client paths do not import Rust or native backend APIs',
      () {
    final files = _runtimeClientFiles();
    expect(files, isNotEmpty);

    const forbidden = [
      'src/rust',
      'flutter_rust_bridge',
      'rust_core.',
      'rust_attachments.',
      'NativeAppBackend',
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source,
          isNot(contains(token)),
          reason: '${file.path} must not contain $token',
        );
      }
    }
  });
}

List<File> _runtimeClientFiles() {
  return [
    ..._dartFiles(Directory('lib/core/cloud')),
    ..._dartFiles(Directory('lib/core/offline_edit')),
    ..._dartFiles(Directory('lib/features/notes')),
    File('lib/features/attachments/attachment_preview_descriptor.dart'),
    File('lib/features/attachments/attachment_storage_controller.dart'),
    File('lib/features/settings/cloud_runtime_mode_page.dart'),
    File('lib/features/settings/vault_usage_card.dart'),
  ];
}

Iterable<File> _dartFiles(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}
