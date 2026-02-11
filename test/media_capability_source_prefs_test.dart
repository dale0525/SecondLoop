import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/media_capability_source_prefs.dart';
import 'package:secondloop/core/ai/media_source_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('source prefs default to auto when unset', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await MediaCapabilitySourcePrefs.readAudio(),
        MediaSourcePreference.auto);
    expect(await MediaCapabilitySourcePrefs.readDocumentOcr(),
        MediaSourcePreference.auto);
  });

  test('source prefs persist independently', () async {
    SharedPreferences.setMockInitialValues({});

    await MediaCapabilitySourcePrefs.write(
      MediaCapabilitySourceScope.audioTranscribe,
      preference: MediaSourcePreference.byok,
    );

    expect(await MediaCapabilitySourcePrefs.readAudio(),
        MediaSourcePreference.byok);
    expect(await MediaCapabilitySourcePrefs.readDocumentOcr(),
        MediaSourcePreference.auto);

    await MediaCapabilitySourcePrefs.write(
      MediaCapabilitySourceScope.documentOcr,
      preference: MediaSourcePreference.cloud,
    );

    expect(await MediaCapabilitySourcePrefs.readAudio(),
        MediaSourcePreference.byok);
    expect(await MediaCapabilitySourcePrefs.readDocumentOcr(),
        MediaSourcePreference.cloud);
  });
}
