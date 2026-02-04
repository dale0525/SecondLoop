import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/media_backup/cloud_media_backup_client.dart';
import 'package:secondloop/features/media_backup/cloud_media_backup_runner.dart';

final class _MemStore implements CloudMediaBackupStore {
  _MemStore(this.items);

  final List<CloudMediaBackupItem> items;
  final Set<String> uploaded = <String>{};
  final Map<String, String> failed = <String, String>{};

  @override
  Future<List<CloudMediaBackupItem>> listDue({
    required int nowMs,
    int limit = 10,
  }) async {
    final due = items
        .where((i) => i.nextRetryAtMs == null || i.nextRetryAtMs! <= nowMs)
        .take(limit)
        .toList(growable: false);
    return due;
  }

  @override
  Future<void> markUploaded({
    required String attachmentSha256,
    required int nowMs,
  }) async {
    uploaded.add(attachmentSha256);
  }

  @override
  Future<void> markFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    failed[attachmentSha256] = error;
    final index =
        items.indexWhere((i) => i.attachmentSha256 == attachmentSha256);
    if (index >= 0) {
      final existing = items[index];
      items[index] = CloudMediaBackupItem(
        attachmentSha256: existing.attachmentSha256,
        desiredVariant: existing.desiredVariant,
        byteLen: existing.byteLen,
        status: 'failed',
        attempts: attempts,
        nextRetryAtMs: nextRetryAtMs,
      );
    }
  }
}

final class _MemClient implements CloudMediaBackupClient {
  bool shouldFail = false;
  final List<String> uploaded = <String>[];

  @override
  Future<void> upload({
    required String attachmentSha256,
    required String desiredVariant,
  }) async {
    if (shouldFail) throw Exception('upload_failed');
    uploaded.add('$attachmentSha256:$desiredVariant');
  }
}

void main() {
  test('disabled => does not upload', () async {
    final store = _MemStore([
      const CloudMediaBackupItem(
        attachmentSha256: 'a',
        desiredVariant: 'webp_q85',
        byteLen: 0,
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
      ),
    ]);
    final client = _MemClient();

    final runner = CloudMediaBackupRunner(
      store: store,
      client: client,
      settings: const CloudMediaBackupRunnerSettings(
        enabled: false,
        wifiOnly: true,
      ),
      getNetwork: () async => CloudMediaBackupNetwork.wifi,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.didUploadAny, isFalse);
    expect(client.uploaded, isEmpty);
  });

  test('enabled + wifi => uploads and marks uploaded', () async {
    final store = _MemStore([
      const CloudMediaBackupItem(
        attachmentSha256: 'a',
        desiredVariant: 'webp_q85',
        byteLen: 0,
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
      ),
    ]);
    final client = _MemClient();

    final runner = CloudMediaBackupRunner(
      store: store,
      client: client,
      settings: const CloudMediaBackupRunnerSettings(
        enabled: true,
        wifiOnly: true,
      ),
      getNetwork: () async => CloudMediaBackupNetwork.wifi,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.didUploadAny, isTrue);
    expect(store.uploaded, contains('a'));
  });

  test('enabled + cellular + wifiOnly => requires confirmation', () async {
    final store = _MemStore([
      const CloudMediaBackupItem(
        attachmentSha256: 'a',
        desiredVariant: 'webp_q85',
        byteLen: 0,
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
      ),
    ]);
    final client = _MemClient();

    final runner = CloudMediaBackupRunner(
      store: store,
      client: client,
      settings: const CloudMediaBackupRunnerSettings(
        enabled: true,
        wifiOnly: true,
      ),
      getNetwork: () async => CloudMediaBackupNetwork.cellular,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.needsCellularConfirmation, isTrue);
    expect(client.uploaded, isEmpty);
  });

  test('upload failure => marks failed and schedules retry', () async {
    final store = _MemStore([
      const CloudMediaBackupItem(
        attachmentSha256: 'a',
        desiredVariant: 'webp_q85',
        byteLen: 0,
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
      ),
    ]);
    final client = _MemClient()..shouldFail = true;

    final runner = CloudMediaBackupRunner(
      store: store,
      client: client,
      settings: const CloudMediaBackupRunnerSettings(
        enabled: true,
        wifiOnly: false,
      ),
      getNetwork: () async => CloudMediaBackupNetwork.wifi,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce();
    expect(result.didUploadAny, isFalse);
    expect(store.failed['a'], isNotNull);
    expect(store.items.single.attempts, 1);
    expect(store.items.single.nextRetryAtMs, greaterThan(1000));
  });
}
