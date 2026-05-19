import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/features/settings/settings_page.dart';

void main() {
  test('web runtime always hides appearance settings', () {
    expect(
      debugShowsAppearancePreferences(
        const AppPlatformCapabilities(
          supportsDesktopHotkey: false,
          supportsAudioRecording: false,
          supportsDesktopDrop: false,
          supportsDesktopBootSettings: false,
          supportsCameraCapture: false,
          usesCloudSessionModel: false,
        ),
        isWeb: true,
      ),
      isFalse,
    );
  });

  test('non-web native runtime keeps appearance settings visible', () {
    expect(
      debugShowsAppearancePreferences(
        AppPlatformCapabilities.native(),
        isWeb: false,
      ),
      isTrue,
    );
  });

  test('web cloud runtime hides appearance settings', () {
    expect(
      debugShowsAppearancePreferences(
        AppPlatformCapabilities.webCloud(),
        isWeb: false,
      ),
      isFalse,
    );
  });
}
