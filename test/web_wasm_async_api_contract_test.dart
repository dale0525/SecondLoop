import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web wasm FRB async APIs are limited to init_app bootstrap only', () {
    final apiFiles = Directory('rust/src/api')
        .listSync()
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

    expect(
      asyncApis,
      <String>['init_app'],
      reason:
          'Non-bootstrap web wasm FRB async APIs bypass the normal worker-pool path and run on the current thread.',
    );
  });

  test('managed-vault pull wire uses the normal worker-pool path', () {
    final generated = File('rust/src/frb_generated.rs').readAsStringSync();
    final start = generated.indexOf(
      'fn wire__crate__api__core__sync_managed_vault_pull_impl(',
    );
    expect(start, isNonNegative);

    final end = generated.indexOf(
      'fn wire__crate__api__core__sync_managed_vault_push_impl(',
      start,
    );
    expect(end, greaterThan(start));

    final section = generated.substring(start, end);
    expect(section, contains('wrap_normal::<'));
    expect(section, isNot(contains('wrap_async::<')));
  });

  test(
      'managed-vault web pull finalization wire uses the normal worker-pool path',
      () {
    final generated = File('rust/src/frb_generated.rs').readAsStringSync();
    final start = generated.indexOf(
      'fn wire__crate__api__web_sync__sync_managed_vault_finalize_web_pull_impl(',
    );
    expect(start, isNonNegative);

    final end = generated.indexOf(
      'fn wire__crate__api__web_sync__sync_managed_vault_read_web_pull_state_impl(',
      start,
    );
    expect(end, greaterThan(start));

    final section = generated.substring(start, end);
    expect(section, contains('wrap_normal::<'));
    expect(section, isNot(contains('wrap_sync::<')));
  });

  test(
      'managed-vault web pull finalization wire stays isolated from sync read path',
      () {
    final generated = File('rust/src/frb_generated.rs').readAsStringSync();
    final start = generated.indexOf(
      'fn wire__crate__api__web_sync__sync_managed_vault_finalize_web_pull_impl(',
    );
    expect(start, isNonNegative);

    final end = generated.indexOf(
      'fn wire__crate__api__web_sync__sync_managed_vault_recover_web_pull_state_impl(',
      start,
    );
    expect(end, greaterThan(start));

    final section = generated.substring(start, end);
    expect(section, contains('wrap_normal::<'));
    expect(
        section,
        contains(
            'fn wire__crate__api__web_sync__sync_managed_vault_read_web_pull_state_impl('));
  });
}
