import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy chat page is fully removed from app and tests', () {
    final root = Directory.current;
    final legacyPageFiles = Directory('lib/features/chat')
        .listSync()
        .whereType<File>()
        .where((file) {
          final name = file.uri.pathSegments.last;
          return name == 'chat_page.dart' ||
              (name.startsWith('chat_page_') && name.endsWith('.dart'));
        })
        .map((file) => file.path)
        .toList()
      ..sort();

    expect(legacyPageFiles, isEmpty);

    const importNeedle = 'features/chat/' '${'chat'}_${'page'}' '.dart';
    final constructorPattern = RegExp(r'(?<![A-Za-z0-9_])ChatPage\(');
    final offenders = <String>[];

    for (final dirName in const ['lib', 'test', 'integration_test']) {
      final dir = Directory('${root.path}/$dirName');
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('legacy_chat_page_removal_test.dart')) {
          continue;
        }

        final source = entity.readAsStringSync();
        if (source.contains(importNeedle) ||
            constructorPattern.hasMatch(source)) {
          offenders.add(entity.path.replaceFirst('${root.path}/', ''));
        }
      }
    }

    offenders.sort();
    expect(offenders, isEmpty);
  });
}
