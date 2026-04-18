import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<String> readRustSource(String path) => File(path).readAsString();

void main() {
  test('wasm init_app installs console panic hook', () async {
    final source = await readRustSource('rust/src/api/simple.rs');
    expect(source, contains('console_error_panic_hook::set_once();'));
  });

  test(
      'managed vault keeps the shared pull loop module and wasm-safe runtime constraints',
      () async {
    final managedVault = await readRustSource('rust/src/sync/managed_vault.rs');
    final pullLoop =
        await readRustSource('rust/src/sync/managed_vault/pull_loop.rs');
    final v2Client =
        await readRustSource('rust/src/sync/managed_vault/v2_client.rs');
    final pullRecovery =
        await readRustSource('rust/src/sync/managed_vault/pull_recovery.rs');
    final runtime =
        await readRustSource('rust/src/sync/managed_vault/runtime.rs');

    expect(File('rust/src/sync/managed_vault/pull.rs').existsSync(), isFalse);
    expect(managedVault, isNot(contains('mod pull;')));
    expect(managedVault, contains('mod pull_loop;'));
    expect(managedVault, contains('pub fn pull('));
    expect(managedVault, contains('pull_loop::pull('));
    expect(
      managedVault,
      contains('fn should_fallback_to_json_pull(status_code: u16) -> bool'),
    );
    expect(pullLoop,
        contains('super::should_fallback_to_json_pull(status.as_u16())'));
    expect(runtime, contains('dedicated web worker path'));
    expect(
      runtime,
      contains('managed-vault sync XHR must run in a dedicated web worker'),
    );
    expect(v2Client, isNot(contains('reqwest::blocking::Client')));
    expect(pullRecovery, isNot(contains('reqwest::blocking::Client')));
  });

  test(
      'managed vault FRB pull entrypoint stays async and offloads non-wasm work',
      () async {
    final core = await readRustSource('rust/src/api/core.rs');

    expect(
      RegExp(
        r'#\[flutter_rust_bridge::frb\]\s+pub async fn sync_managed_vault_pull\(',
        multiLine: true,
      ).hasMatch(core),
      isTrue,
    );
    expect(
      core,
      contains('sync::managed_vault::pull('),
    );
    expect(
      core,
      contains('tokio::task::spawn_blocking'),
    );
    expect(core, contains('#[cfg(target_family = "wasm")]'));
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
