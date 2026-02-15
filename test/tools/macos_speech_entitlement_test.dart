import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macos entitlements enable speech recognition access', () {
    const files = <String>[
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ];

    for (final path in files) {
      final content = File(path).readAsStringSync();
      expect(
        content,
        contains(
          RegExp(
            r'<key>com\.apple\.security\.personal-information\.speech-recognition</key>\s*<true\s*/>',
            multiLine: true,
          ),
        ),
        reason: 'missing speech-recognition entitlement in $path',
      );
    }
  });
}
