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
}
