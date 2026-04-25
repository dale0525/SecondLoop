import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _wireSection(String fnName) {
  final generated = File('rust/src/frb_generated.rs').readAsStringSync();
  final start = generated.indexOf('fn $fnName(');
  expect(start, isNonNegative);

  final nextFn = generated.indexOf('\nfn wire__', start + 1);
  final end = nextFn == -1 ? generated.length : nextFn;
  expect(end, greaterThan(start));

  return generated.substring(start, end);
}

void main() {
  test('web wasm FRB async APIs are limited to audited entrypoints', () {
    final apiFiles = Directory('rust/src/api')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.rs'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final asyncApis = <String>[];
    final pattern = RegExp(
      r'#\[flutter_rust_bridge::frb(?:\([^\)]*\))?\]\s*pub async fn ([a-zA-Z0-9_]+)',
      multiLine: true,
    );

    for (final file in apiFiles) {
      final source = file.readAsStringSync();
      asyncApis.addAll(
        pattern.allMatches(source).map((match) => match.group(1)!),
      );
    }
    asyncApis.sort();

    expect(
      asyncApis,
      <String>['init_app', 'sync_managed_vault_pull'],
      reason:
          'FRB async APIs bypass the normal worker-pool path, so each non-bootstrap entrypoint needs an explicit runtime contract.',
    );
  });

  test('managed-vault pull wire uses the async bridge path', () {
    final section =
        _wireSection('wire__crate__api__core__sync_managed_vault_pull_impl');
    final pullEntrypoint =
        File('rust/src/api/core_parts/part_05.rs').readAsStringSync();

    expect(section, contains('wrap_async::<'));
    expect(section, isNot(contains('wrap_normal::<')));
    expect(section, contains('crate::api::core::sync_managed_vault_pull('));
    expect(section, contains('.await'));
    expect(pullEntrypoint, contains('tokio::task::spawn_blocking'));
    expect(pullEntrypoint, contains('#[cfg(target_family = "wasm")]'));
  });

  test(
      'managed-vault web pull finalization wire uses the normal worker-pool path',
      () {
    final section = _wireSection(
      'wire__crate__api__web_sync__sync_managed_vault_finalize_web_pull_impl',
    );
    expect(section, contains('wrap_normal::<'));
    expect(section, isNot(contains('wrap_sync::<')));
  });

  test(
      'managed-vault web pull finalization wire stays isolated from sync read path',
      () {
    final section = _wireSection(
      'wire__crate__api__web_sync__sync_managed_vault_finalize_web_pull_impl',
    );
    expect(section, contains('wrap_normal::<'));
    expect(
      section,
      isNot(
        contains(
          'wire__crate__api__web_sync__sync_managed_vault_read_web_pull_state_impl',
        ),
      ),
    );
  });

  test('managed-vault web pull read wire uses the normal worker-pool path', () {
    final section = _wireSection(
      'wire__crate__api__web_sync__sync_managed_vault_read_web_pull_state_impl',
    );
    expect(section, contains('wrap_normal::<'));
    expect(section, isNot(contains('wrap_sync::<')));
  });

  test('managed-vault web pull apply wire uses the normal worker-pool path',
      () {
    final section = _wireSection(
      'wire__crate__api__web_sync__sync_managed_vault_apply_web_pull_page_impl',
    );
    expect(section, contains('wrap_normal::<'));
    expect(section, isNot(contains('wrap_sync::<')));
  });

  test('managed-vault web pull recovery wire uses the normal worker-pool path',
      () {
    final section = _wireSection(
      'wire__crate__api__web_sync__sync_managed_vault_recover_web_pull_state_impl',
    );
    expect(section, contains('wrap_normal::<'));
    expect(section, isNot(contains('wrap_sync::<')));
  });
}
