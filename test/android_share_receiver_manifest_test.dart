import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android ShareReceiverActivity accepts generic files', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:name=".ShareReceiverActivity"'));
    expect(manifest, contains('<data android:mimeType="*/*"/>'));
  });
}
