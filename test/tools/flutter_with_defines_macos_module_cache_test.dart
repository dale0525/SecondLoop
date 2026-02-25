import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_with_defines prefers project flutter sdk before dart+fvm', () {
    final content = File('scripts/flutter_with_defines.sh').readAsStringSync();

    expect(content, contains('.fvm/flutter_sdk/bin/flutter'));
    expect(content, contains(r'if [[ -x "${project_flutter}" ]]'));
    expect(content, contains(r'exec "${project_flutter}" "${args[@]}"'));

    final projectFlutterIndex = content.indexOf('.fvm/flutter_sdk/bin/flutter');
    final dartProbeIndex = content.indexOf('if command -v dart');

    expect(projectFlutterIndex, greaterThanOrEqualTo(0));
    expect(dartProbeIndex, greaterThan(projectFlutterIndex));
  });

  test('flutter_with_defines disables implicit pub get for run/build', () {
    final content = File('scripts/flutter_with_defines.sh').readAsStringSync();

    expect(content, contains('has_pub_resolution_flag()'));
    expect(content, contains('maybe_disable_implicit_pub_get()'));
    expect(content, contains(r'case "${all_args[0]}" in'));
    expect(content, contains('run|build'));
    expect(content, contains(r'all_args+=("--no-pub")'));
    expect(content, contains('\nmaybe_disable_implicit_pub_get\n'));
  });

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
    expect(
        content, contains('/usr/bin/codesign --verify --strict --verbose=2'));

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
