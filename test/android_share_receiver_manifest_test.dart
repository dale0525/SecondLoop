import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android ShareReceiverActivity accepts generic files', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:name=".ShareReceiverActivity"'));
    expect(manifest, contains('<data android:mimeType="*/*"/>'));
  });

  test('Android ShareReceiverActivity supports multi-file share intents', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/secondloop/secondloop/ShareReceiverActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
    expect(receiver, contains('Intent.ACTION_SEND_MULTIPLE'));
    expect(
      receiver,
      contains('getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)'),
    );
  });
}
