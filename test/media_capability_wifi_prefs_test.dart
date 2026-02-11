import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/media_capability_wifi_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scoped wifi prefs fallback to legacy default when unset', () async {
    SharedPreferences.setMockInitialValues({});

    expect(
      await MediaCapabilityWifiPrefs.readAudioWifiOnly(
        fallbackWifiOnly: true,
      ),
      isTrue,
    );
    expect(
      await MediaCapabilityWifiPrefs.readOcrWifiOnly(
        fallbackWifiOnly: false,
      ),
      isFalse,
    );
    expect(
      await MediaCapabilityWifiPrefs.readImageWifiOnly(
        fallbackWifiOnly: true,
      ),
      isTrue,
    );
  });

  test('scoped wifi prefs persist independently', () async {
    SharedPreferences.setMockInitialValues({});

    await MediaCapabilityWifiPrefs.write(
      MediaCapabilityWifiScope.audioTranscribe,
      wifiOnly: false,
    );

    expect(
      await MediaCapabilityWifiPrefs.readAudioWifiOnly(
        fallbackWifiOnly: true,
      ),
      isFalse,
    );
    expect(
      await MediaCapabilityWifiPrefs.readOcrWifiOnly(
        fallbackWifiOnly: true,
      ),
      isTrue,
    );
    expect(
      await MediaCapabilityWifiPrefs.readImageWifiOnly(
        fallbackWifiOnly: true,
      ),
      isTrue,
    );

    await MediaCapabilityWifiPrefs.write(
      MediaCapabilityWifiScope.documentOcr,
      wifiOnly: false,
    );

    expect(
      await MediaCapabilityWifiPrefs.readAudioWifiOnly(
        fallbackWifiOnly: true,
      ),
      isFalse,
    );
    expect(
      await MediaCapabilityWifiPrefs.readOcrWifiOnly(
        fallbackWifiOnly: true,
      ),
      isFalse,
    );
    expect(
      await MediaCapabilityWifiPrefs.readImageWifiOnly(
        fallbackWifiOnly: true,
      ),
      isTrue,
    );
  });

  test('writeAll updates every scoped wifi preference', () async {
    SharedPreferences.setMockInitialValues({});

    await MediaCapabilityWifiPrefs.writeAll(wifiOnly: false);

    expect(
      await MediaCapabilityWifiPrefs.readAudioWifiOnly(
        fallbackWifiOnly: true,
      ),
      isFalse,
    );
    expect(
      await MediaCapabilityWifiPrefs.readOcrWifiOnly(
        fallbackWifiOnly: true,
      ),
      isFalse,
    );
    expect(
      await MediaCapabilityWifiPrefs.readImageWifiOnly(
        fallbackWifiOnly: true,
      ),
      isFalse,
    );
  });
}
