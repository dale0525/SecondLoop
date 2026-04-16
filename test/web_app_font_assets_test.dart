import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec declares bundled web app brand fonts', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('- family: Inter'));
    expect(pubspec, contains('- family: Sora'));
    expect(pubspec, contains('assets/fonts/inter/Inter-Variable.ttf'));
    expect(pubspec, contains('assets/fonts/sora/Sora-Variable.ttf'));
  });
}
