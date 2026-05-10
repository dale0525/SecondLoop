import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('run_build_tool retries pub get after clearing advisory cache', () {
    final content =
        File('rust_builder/cargokit/run_build_tool.sh').readAsStringSync();

    expect(content, contains('clear_pub_advisories_cache()'));
    expect(content, contains('run_pub_get_with_retry()'));
    expect(content, contains('*-advisories.json'));
    expect(content, contains('SecondLoop: dart pub get failed;'));
    expect(content, contains('run_pub_get_with_retry'));
  });

  test('build_pod does not dump raw Xcode environment', () {
    final content =
        File('rust_builder/cargokit/build_pod.sh').readAsStringSync();

    expect(content, isNot(contains('\nenv\n')));
  });
}
