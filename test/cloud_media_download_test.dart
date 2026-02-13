import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/media_backup/cloud_media_backup_runner.dart';
import 'package:secondloop/features/media_backup/cloud_media_download.dart';

import 'test_backend.dart';

final class _DownloadBackend extends TestAppBackend {
  int webdavCalls = 0;
  int localDirCalls = 0;
  int managedVaultCalls = 0;
  Duration webdavDelay = Duration.zero;

  final List<String> webdavDownloadShas = <String>[];

  @override
  Future<void> syncWebdavDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    webdavCalls += 1;
    webdavDownloadShas.add(sha256);
    if (webdavDelay > Duration.zero) {
      await Future<void>.delayed(webdavDelay);
    }
  }

  @override
  Future<void> syncLocaldirDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
    required String sha256,
  }) async {
    localDirCalls += 1;
  }

  @override
  Future<void> syncManagedVaultDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    managedVaultCalls += 1;
  }
}

void main() {
  test('CloudMediaDownload asks for confirmation on cellular when wifi-only',
      () async {
    SharedPreferences.setMockInitialValues({
      'sync_config_plain_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'webdav',
        SyncConfigStore.kRemoteRoot: 'SecondLoopTest',
        SyncConfigStore.kWebdavBaseUrl: 'https://example.com/webdav',
        SyncConfigStore.kSyncKeyB64: base64Encode(List<int>.filled(32, 1)),
        SyncConfigStore.kChatThumbnailsWifiOnly: '1',
      }),
    });

    final backend = _DownloadBackend();
    final downloader = CloudMediaDownload(
      networkProvider: () async => CloudMediaBackupNetwork.cellular,
    );

    final result =
        await downloader.downloadAttachmentBytesFromConfiguredSyncWithPolicy(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
      sha256: 'sha-test',
      allowCellular: false,
    );

    expect(result.didDownload, isFalse);
    expect(result.needsCellularConfirmation, isTrue);
    expect(backend.webdavCalls, 0);
  });

  test('CloudMediaDownload proceeds when cellular is explicitly allowed',
      () async {
    SharedPreferences.setMockInitialValues({
      'sync_config_plain_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'webdav',
        SyncConfigStore.kRemoteRoot: 'SecondLoopTest',
        SyncConfigStore.kWebdavBaseUrl: 'https://example.com/webdav',
        SyncConfigStore.kSyncKeyB64: base64Encode(List<int>.filled(32, 1)),
        SyncConfigStore.kChatThumbnailsWifiOnly: '1',
      }),
    });

    final backend = _DownloadBackend();
    final downloader = CloudMediaDownload(
      networkProvider: () async => CloudMediaBackupNetwork.cellular,
    );

    final result =
        await downloader.downloadAttachmentBytesFromConfiguredSyncWithPolicy(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
      sha256: 'sha-test',
      allowCellular: true,
    );

    expect(result.didDownload, isTrue);
    expect(result.needsCellularConfirmation, isFalse);
    expect(backend.webdavCalls, 1);
  });

  test('CloudMediaDownload local dir ignores cellular gating', () async {
    SharedPreferences.setMockInitialValues({
      'sync_config_plain_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'localdir',
        SyncConfigStore.kRemoteRoot: 'SecondLoopTest',
        SyncConfigStore.kLocalDir: '/tmp/secondloop-test',
        SyncConfigStore.kSyncKeyB64: base64Encode(List<int>.filled(32, 1)),
        SyncConfigStore.kChatThumbnailsWifiOnly: '1',
      }),
    });

    final backend = _DownloadBackend();
    final downloader = CloudMediaDownload(
      networkProvider: () async => CloudMediaBackupNetwork.cellular,
    );

    final result =
        await downloader.downloadAttachmentBytesFromConfiguredSyncWithPolicy(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
      sha256: 'sha-test',
      allowCellular: false,
    );

    expect(result.didDownload, isTrue);
    expect(result.needsCellularConfirmation, isFalse);
    expect(backend.localDirCalls, 1);
  });

  test('CloudMediaDownload deduplicates concurrent downloads for same sha',
      () async {
    SharedPreferences.setMockInitialValues({
      'sync_config_plain_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'webdav',
        SyncConfigStore.kRemoteRoot: 'SecondLoopTest',
        SyncConfigStore.kWebdavBaseUrl: 'https://example.com/webdav',
        SyncConfigStore.kSyncKeyB64: base64Encode(List<int>.filled(32, 1)),
      }),
    });

    final backend = _DownloadBackend();
    backend.webdavDelay = const Duration(milliseconds: 80);
    final downloader = CloudMediaDownload(
      networkProvider: () async => CloudMediaBackupNetwork.wifi,
    );

    final futures = <Future<CloudMediaDownloadResult>>[
      downloader.downloadAttachmentBytesFromConfiguredSyncWithPolicy(
        backend: backend,
        sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
        sha256: 'sha-test',
        allowCellular: false,
      ),
      downloader.downloadAttachmentBytesFromConfiguredSyncWithPolicy(
        backend: backend,
        sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
        sha256: 'sha-test',
        allowCellular: false,
      ),
    ];

    final results = await Future.wait(futures);
    expect(results.every((r) => r.didDownload), isTrue);
    expect(
      results.every((r) => r.needsCellularConfirmation == false),
      isTrue,
    );
    expect(backend.webdavCalls, 1);
    expect(backend.webdavDownloadShas, ['sha-test']);
  });
}
