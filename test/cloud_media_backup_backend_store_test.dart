import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/media_backup/cloud_media_backup_runner.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  test('backend cloud media backup store stays bound to its explicit scope',
      () async {
    final backend = _ScopeRecordingBackend();
    final store = BackendCloudMediaBackupStore(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      scopeId: 'scope-a',
    );

    await store.listDue(nowMs: 1000, limit: 10);
    await store.markUploaded(attachmentSha256: 'sha-a', nowMs: 1000);
    await store.markFailed(
      attachmentSha256: 'sha-a',
      error: 'upload_failed',
      attempts: 1,
      nextRetryAtMs: 2000,
      nowMs: 1000,
    );

    expect(backend.scopes, <String?>['scope-a', 'scope-a', 'scope-a']);
  });
}

final class _ScopeRecordingBackend extends TestAppBackend {
  final List<String?> scopes = <String?>[];

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
    String? scopeId,
  }) async {
    scopes.add(scopeId);
    return const <CloudMediaBackup>[];
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
    String? scopeId,
  }) async {
    scopes.add(scopeId);
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
    String? scopeId,
  }) async {
    scopes.add(scopeId);
  }
}
