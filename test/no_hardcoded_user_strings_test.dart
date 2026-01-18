import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No hardcoded user-facing strings in lib/', () {
    final disallowedPatterns = <RegExp>[
      RegExp(r'''Text\(\s*['"]'''),
      RegExp(r'''labelText:\s*['"]'''),
      RegExp(r'''hintText:\s*['"]'''),
      RegExp(r'''tooltip:\s*['"]'''),
      RegExp(r'''localizedReason:\s*['"]'''),
    ];

    final excludedPaths = <String>{
      'lib/i18n/strings.g.dart',
      'lib/src/rust/frb_generated.dart',
      'lib/src/rust/frb_generated.io.dart',
      'lib/src/rust/frb_generated.web.dart',
    };

    final offenders = <String>[];
    final libDir = Directory('lib');
    if (!libDir.existsSync()) {
      fail('Missing lib/ directory');
    }

    for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (excludedPaths.contains(entity.path)) continue;

      final content = entity.readAsStringSync();
      for (final pattern in disallowedPatterns) {
        if (!pattern.hasMatch(content)) continue;
        offenders.add('${entity.path}: matches ${pattern.pattern}');
        break;
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
