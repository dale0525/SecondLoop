import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/app.dart';
import 'package:secondloop/core/navigation/inherited_scope_page_wrapper.dart';
import 'package:secondloop/core/sync/sync_key_manager.dart';

void main() {
  tearDown(SyncKeyManager.resetForTest);

  test('root settings scope drops stale captured session after lock', () {
    final capturedScopes = InheritedScopeCapture(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
      lock: () {},
    );

    SyncKeyManager.setSessionKey(null);

    expect(
      resolveRootSettingsInheritedScopes(capturedScopes),
      isNull,
    );
  });

  test('root settings scope keeps capture while session remains unlocked', () {
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 9));
    final capturedScopes = InheritedScopeCapture(
      sessionKey: sessionKey,
      lock: () {},
    );

    SyncKeyManager.setSessionKey(sessionKey);

    expect(
      resolveRootSettingsInheritedScopes(capturedScopes),
      same(capturedScopes),
    );
  });

  test('root settings scope drops stale captured session after re-unlock', () {
    final capturedScopes = InheritedScopeCapture(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
      lock: () {},
    );

    SyncKeyManager.setSessionKey(
      Uint8List.fromList(List<int>.filled(32, 8)),
    );

    expect(
      resolveRootSettingsInheritedScopes(capturedScopes),
      isNull,
    );
  });
}
