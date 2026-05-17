import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';

void main() {
  testWidgets('SyncEngineGate does not create a local-first sync engine',
      (tester) async {
    SyncEngineScope? scope;

    await tester.pumpWidget(
      MaterialApp(
        home: SyncEngineGate(
          child: Builder(
            builder: (context) {
              scope =
                  context.dependOnInheritedWidgetOfExactType<SyncEngineScope>();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(scope, isNotNull);
    expect(scope!.engine, isNull);
  });

  test('SyncEngineGate source stays out of legacy sync orchestration', () {
    final source =
        File('lib/core/sync/sync_engine_gate.dart').readAsStringSync();

    for (final token in [
      'SyncEngine(',
      'ConnectivityPlatform',
      'SyncConfigStore',
      'syncWebdavPush',
      'syncLocaldirPush',
      'syncManagedVaultPush',
      'managedVaultUploadAttachment',
      'cloudMediaBackup',
    ]) {
      expect(source, isNot(contains(token)), reason: token);
    }
  });

  test('legacy media-upload gate test parts are retired', () {
    for (final path in [
      'test/sync_engine_gate_media_uploads_test_helpers.dart',
      'test/sync_engine_gate_media_uploads_test_webdav.dart',
      'test/sync_engine_gate_media_uploads_test_managed_vault.dart',
      'test/sync_engine_gate_media_uploads_test_gate_state.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('write gate scope helper keeps deterministic comparison semantics', () {
    expect(
      shouldApplySyncEngineGateWriteGateRehydration(
        requestVersion: 1,
        latestVersion: 1,
        expectedBackendType: null,
        activeBackendType: null,
        expectedScopeId: 'runtime-profile',
        activeScopeId: 'runtime-profile',
      ),
      isTrue,
    );

    expect(
      shouldApplySyncEngineGateWriteGateRehydration(
        requestVersion: 1,
        latestVersion: 2,
        expectedBackendType: null,
        activeBackendType: null,
        expectedScopeId: 'runtime-profile',
        activeScopeId: 'runtime-profile',
      ),
      isFalse,
    );
  });
}
