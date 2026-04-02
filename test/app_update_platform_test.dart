import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/update/app_update_platform.dart';

void main() {
  group('parseArchitectureHintFromPlatformVersion', () {
    test('extracts architecture token from dart platform version suffix', () {
      expect(
        parseArchitectureHintFromPlatformVersion(
          '3.4.4 (stable) on "windows_x64"',
        ),
        'windows_x64',
      );
      expect(
        parseArchitectureHintFromPlatformVersion(
          '3.6.0 (stable) on "macos_arm64"',
        ),
        'macos_arm64',
      );
    });

    test('falls back to raw version string when suffix is missing', () {
      expect(
        parseArchitectureHintFromPlatformVersion('3.4.4 (stable)'),
        '3.4.4 (stable)',
      );
    });

    test('returns unknown for empty values', () {
      expect(parseArchitectureHintFromPlatformVersion(''), 'unknown');
      expect(parseArchitectureHintFromPlatformVersion('   '), 'unknown');
    });
  });
}
