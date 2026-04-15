import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime rust modules avoid direct OsRng usage', () {
    final crypto = File('rust/src/crypto/mod.rs').readAsStringSync();
    final auth = File('rust/src/auth/mod.rs').readAsStringSync();
    final recovery = File('rust/src/sync/recovery_key.rs').readAsStringSync();

    expect(
      RegExp(r'OsRng\.fill_bytes').allMatches(crypto).length,
      1,
    );
    expect(auth, isNot(contains('OsRng.fill_bytes')));
    expect(recovery, isNot(contains('OsRng.fill_bytes')));
    expect(crypto, contains('fill_random_bytes('));
    expect(auth, contains('fill_random_bytes('));
    expect(recovery, contains('fill_random_bytes('));
  });

  test('managed vault wasm xhr copies request body into JS-owned buffer', () {
    final runtime =
        File('rust/src/sync/managed_vault/runtime.rs').readAsStringSync();

    expect(
      runtime,
      contains('Uint8Array::new_with_length(body.len() as u32)'),
    );
    expect(runtime, contains('js_body.copy_from(body.as_slice())'));
    expect(runtime, contains('send_with_opt_js_u8_array(Some(&js_body))'));
    expect(
      runtime,
      isNot(contains('send_with_opt_u8_array(Some(body.as_slice()))')),
    );
    expect(runtime, isNot(contains('Uint8Array::view(body.as_slice())')));
  });
}
