import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'android native transcode preserves source pcm timing when re-encoding to m4a',
    () {
      final content = File(
        'android/app/src/main/kotlin/com/secondloop/secondloop/MainActivity.kt',
      ).readAsStringSync();

      expect(content, contains('val targetSampleRate = inputSampleRate'));
      expect(content,
          contains('val targetChannelCount = maxOf(1, inputChannelCount)'));
      expect(
        content,
        isNot(contains(
            'maxOf(8000, if (sampleRateHz > 0) sampleRateHz else inputSampleRate)')),
      );
      expect(content,
          isNot(contains('if (mono) 1 else maxOf(1, inputChannelCount)')));
    },
  );
}
