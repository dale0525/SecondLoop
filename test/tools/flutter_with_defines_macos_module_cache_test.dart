import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_with_defines cleans macOS module cache conflicts', () {
    final content = File('scripts/flutter_with_defines.sh').readAsStringSync();

    expect(content, contains('maybe_clear_macos_module_cache_conflict'));
    expect(content, contains('FlutterMacOS-*.pcm'));
    expect(content, contains('build/macos/ModuleCache.noindex'));
    expect(content, contains(r'rm -rf "${module_cache_root}"'));

    final declarationIndex =
        content.indexOf('maybe_clear_macos_module_cache_conflict()');
    final invocationIndex =
        content.indexOf('\nmaybe_clear_macos_module_cache_conflict\n');

    expect(declarationIndex, greaterThanOrEqualTo(0));
    expect(invocationIndex, greaterThan(declarationIndex));
  });

  test(
      'flutter_with_defines clears stale macOS app bundle without privacy keys',
      () {
    final content = File('scripts/flutter_with_defines.sh').readAsStringSync();

    expect(
      content,
      contains('maybe_clear_macos_stale_app_bundle_for_speech_privacy()'),
    );
    expect(content, contains('NSSpeechRecognitionUsageDescription'));
    expect(content, contains('NSMicrophoneUsageDescription'));
    expect(
      content,
      contains('build/macos/Build/Products/Debug/SecondLoop.app'),
    );
    expect(content, contains(r'rm -rf "${app_bundle_dir}"'));

    final declarationIndex = content.indexOf(
      'maybe_clear_macos_stale_app_bundle_for_speech_privacy()',
    );
    final invocationIndex = content.indexOf(
      '\nmaybe_clear_macos_stale_app_bundle_for_speech_privacy\n',
    );

    expect(declarationIndex, greaterThanOrEqualTo(0));
    expect(invocationIndex, greaterThan(declarationIndex));
  });
}
