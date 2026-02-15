import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tools/sync_desktop_runtime_to_appdir.dart' as runtime_sync;

void main() {
  test('windows default bundle id maps to company/product app support path',
      () {
    const appData = 'appdata-root';
    final resolved = runtime_sync.resolveWindowsAppSupportDirForTest(
      appData: appData,
      bundleId: 'com.secondloop.secondloop',
    );

    final expected = [
      appData,
      'com.secondloop',
      'SecondLoop',
    ].join(Platform.pathSeparator);
    expect(resolved, expected);
  });

  test('windows custom bundle id keeps direct APPDATA subdirectory', () {
    const appData = 'appdata-root';
    final resolved = runtime_sync.resolveWindowsAppSupportDirForTest(
      appData: appData,
      bundleId: 'org.example.custom',
    );

    final expected =
        [appData, 'org.example.custom'].join(Platform.pathSeparator);
    expect(resolved, expected);
  });
}
