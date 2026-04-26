import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<String> readRustSource(String path) => File(path).readAsString();

void main() {
  test('wasm init_app installs console panic hook', () async {
    final source = await readRustSource('rust/src/api/simple.rs');
    expect(source, contains('console_error_panic_hook::set_once();'));
  });

  test('managed vault keeps the v2 pull path and wasm-safe runtime constraints',
      () async {
    final managedVault = await readRustSource('rust/src/sync/managed_vault.rs');
    final globalLogClient = await readRustSource(
        'rust/src/sync/managed_vault/global_log_client.rs');
    final runtime =
        await readRustSource('rust/src/sync/managed_vault/runtime.rs');

    expect(File('rust/src/sync/managed_vault/pull.rs').existsSync(), isFalse);
    expect(managedVault, isNot(contains('mod pull;')));
    expect(managedVault, contains('mod global_log_client;'));
    expect(managedVault, contains('pub fn pull('));
    expect(managedVault, contains('global_log_client::pull_v2('));
    expect(managedVault, contains('finalize_v2_pull_blob_backfill('));
    expect(runtime, contains('dedicated web worker path'));
    expect(
      runtime,
      contains('managed-vault sync XHR must run in a dedicated web worker'),
    );
    expect(globalLogClient, isNot(contains('reqwest::blocking::Client')));
  });

  test(
      'managed vault FRB pull entrypoint stays async and offloads non-wasm work',
      () async {
    final core = await readRustSource('rust/src/api/core.rs');
    final pullEntrypoint =
        await readRustSource('rust/src/api/core_parts/part_05.rs');

    expect(core, contains('include!("core_parts/part_05.rs");'));
    expect(
      RegExp(
        r'#\[flutter_rust_bridge::frb\]\s+pub async fn sync_managed_vault_pull\(',
        multiLine: true,
      ).hasMatch(pullEntrypoint),
      isTrue,
    );
    expect(
      pullEntrypoint,
      contains('sync::managed_vault::pull('),
    );
    expect(
      pullEntrypoint,
      contains('tokio::task::spawn_blocking'),
    );
    expect(pullEntrypoint, contains('#[cfg(target_family = "wasm")]'));
  });

  test(
      'wasm shared rust modules use platform time helper instead of SystemTime',
      () async {
    const sharedModules = <String>[
      'rust/src/db/parts/01_prelude.rs',
      'rust/src/rag/context_selection.rs',
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
