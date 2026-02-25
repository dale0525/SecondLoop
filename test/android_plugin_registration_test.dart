import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android MainActivity explicitly registers generated plugins', () {
    final mainActivity = File(
            'android/app/src/main/kotlin/com/secondloop/secondloop/MainActivity.kt')
        .readAsStringSync();

    expect(
      mainActivity,
      contains('GeneratedPluginRegistrant.registerWith(flutterEngine)'),
    );
  });
}
