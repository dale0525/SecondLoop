import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/oplog_maintenance_scope.dart';

String _decodeBase64UrlNoPad(String value) {
  final normalized = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return utf8.decode(base64Url.decode(normalized));
}

void main() {
  test('managed vault scope id uses managed_vault|base|vault raw payload', () {
    final scopeId = computeOplogMaintenanceScopeId(
      const OplogMaintenanceScopeInput(
        backendType: SyncBackendType.managedVault,
        baseUrl: ' https://vault.example.com/api ',
        localDir: null,
        remoteRoot: ' vault-1 ',
      ),
    );

    expect(
      _decodeBase64UrlNoPad(scopeId),
      'managed_vault|https://vault.example.com/api|vault-1',
    );
  });

  test('webdav scope id sanitizes target id and normalizes remote root', () {
    final scopeId = computeOplogMaintenanceScopeId(
      const OplogMaintenanceScopeInput(
        backendType: SyncBackendType.webdav,
        baseUrl: 'https://user:pw@example.com/dav?token=1#frag',
        localDir: null,
        remoteRoot: 'SecondLoop',
      ),
    );

    expect(
      _decodeBase64UrlNoPad(scopeId),
      'webdav:https://example.com/dav/|/SecondLoop/',
    );
  });

  test('localdir scope id uses normalized root and localdir target id', () {
    final scopeId = computeOplogMaintenanceScopeId(
      const OplogMaintenanceScopeInput(
        backendType: SyncBackendType.localDir,
        baseUrl: null,
        localDir: '/tmp/secondloop',
        remoteRoot: '/SecondLoop/',
      ),
    );

    expect(
      _decodeBase64UrlNoPad(scopeId),
      'localdir:/tmp/secondloop|/SecondLoop/',
    );
  });
}
