import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<String> readRustSource(String path) => File(path).readAsString();

void main() {
  test('wasm init_app installs console panic hook', () async {
    final source = await readRustSource('rust/src/api/simple.rs');
    expect(source, contains('console_error_panic_hook::set_once();'));
  });

  test('wasm managed vault pull starts with json fallback instead of pull_bin',
      () async {
    final source = await readRustSource('rust/src/sync/managed_vault.rs');
    expect(source, contains('fn should_try_pull_bin_first() -> bool'));
    expect(source, contains('#[cfg(target_family = "wasm")]'));
    expect(source, contains('false'));
  });

  test(
      'wasm shared rust modules use platform time helper instead of SystemTime',
      () async {
    const sharedModules = <String>[
      'rust/src/db/parts/01_prelude.rs',
      'rust/src/knowledge/chunk.rs',
      'rust/src/knowledge/index_jobs.rs',
      'rust/src/knowledge/usage.rs',
      'rust/src/rag/context_selection.rs',
      'rust/src/rag/mod.rs',
      'rust/src/sync/parts/02_push.rs',
    ];

    final helperSource = await readRustSource('rust/src/platform/time.rs');
    expect(helperSource, contains('pub fn now_ms() -> i64'));
    expect(helperSource, contains('js_sys::Date::now()'));

    for (final path in sharedModules) {
      final source = await readRustSource(path);
      expect(
        source,
        isNot(contains('SystemTime::now()')),
        reason: '$path should avoid std::time on wasm',
      );
      expect(
        source,
        contains('platform::time::now_ms'),
        reason: '$path should reuse the shared platform time helper',
      );
    }
  });
}
