import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  testWidgets('Media uploads off => sync uses ops-only push (WebDAV)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend();

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.webdavPushCalls == 0 &&
            backend.webdavPushOpsOnlyCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.webdavPushCalls, 0);
      expect(backend.webdavPushOpsOnlyCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets('Media uploads on => uploads due items automatically (WebDAV)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend(
        dueBackups: [
          const CloudMediaBackup(
            attachmentSha256: 'a',
            desiredVariant: 'original',
            byteLen: 0,
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            updatedAtMs: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.webdavUploadAttachmentCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.webdavPushOpsOnlyCalls, greaterThanOrEqualTo(1));
      expect(backend.webdavUploadAttachmentCalls, 1);
      expect(backend.markUploadedCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets('Media uploads on => auto-backfills cloud media queue once',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend();

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.cloudMediaBackfillCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.cloudMediaBackfillCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });
}

final class _FakeConnectivityPlatform extends ConnectivityPlatform {
  _FakeConnectivityPlatform._(this._results);

  factory _FakeConnectivityPlatform.wifi() {
    return _FakeConnectivityPlatform._(
      const <ConnectivityResult>[ConnectivityResult.wifi],
    );
  }

  final List<ConnectivityResult> _results;

  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _results;
}

final class _RecordingBackend extends TestAppBackend {
  _RecordingBackend({List<CloudMediaBackup>? dueBackups})
      : _dueBackups = List<CloudMediaBackup>.from(dueBackups ?? const []);

  int webdavPushCalls = 0;
  int webdavPushOpsOnlyCalls = 0;
  int webdavUploadAttachmentCalls = 0;
  int markUploadedCalls = 0;
  int cloudMediaBackfillCalls = 0;

  final List<CloudMediaBackup> _dueBackups;
  final Set<String> _uploaded = <String>{};

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavPushCalls++;
    return 0;
  }

  @override
  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavPushOpsOnlyCalls++;
    return 0;
  }

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
  }) async {
    return _dueBackups
        .where((b) => !_uploaded.contains(b.attachmentSha256))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
  }) async {
    markUploadedCalls++;
    _uploaded.add(attachmentSha256);
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    // ignored
  }

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
  }) async {
    cloudMediaBackfillCalls++;
    return 0;
  }

  @override
  Future<bool> syncWebdavUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    webdavUploadAttachmentCalls++;
    return true;
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;
}
