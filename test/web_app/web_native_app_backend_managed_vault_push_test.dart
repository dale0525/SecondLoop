import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/web_app/web_app_service.dart';
import 'package:secondloop/web_app/web_formal_settings_adapters.dart';
import 'package:secondloop/web_app/web_native_app_backend.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('WebNativeAppBackend continues after no-op media repairs succeed',
      () async {
    final service = _ManagedVaultPushBridgeService();
    const deleteAction = ManagedVaultV2PushMediaAction(
      kind: ManagedVaultV2PushMediaActionKind.attachmentDelete,
      remoteId: 'sha-deleted',
      sha256: 'sha-deleted',
    );
    const uploadAction = ManagedVaultV2PushMediaAction(
      kind: ManagedVaultV2PushMediaActionKind.attachmentUpload,
      remoteId: 'sha-fresh',
      sha256: 'sha-fresh',
      mimeType: 'image/png',
      createdAtMs: 100,
    );
    final backend = _ManagedVaultPushBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
      mediaUploads: <ManagedVaultV2PushMediaUpload>[
        ManagedVaultV2PushMediaUpload(
          hasBody: true,
          remoteId: 'sha-fresh',
          mimeType: 'image/png',
          createdAtMs: 100,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ],
      batches: <ManagedVaultV2PushBatch>[
        ManagedVaultV2PushBatch(
          hasOps: false,
          opCount: 0,
          request: null,
          mediaActions: const <ManagedVaultV2PushMediaAction>[deleteAction],
          mediaPhase: ManagedVaultV2PushMediaPhase.repairs,
          batchJson: _batchJson(
            mediaPhase: 'repairs',
            mediaActions: <Object?>[deleteAction.toJson()],
          ),
        ),
        ManagedVaultV2PushBatch(
          hasOps: false,
          opCount: 0,
          request: null,
          mediaActions: const <ManagedVaultV2PushMediaAction>[uploadAction],
          mediaPhase: ManagedVaultV2PushMediaPhase.freshDevice,
          batchJson: _batchJson(
            mediaPhase: 'fresh_device',
            mediaActions: <Object?>[uploadAction.toJson()],
          ),
        ),
        ManagedVaultV2PushBatch(
          hasOps: false,
          opCount: 0,
          request: null,
          batchJson: _batchJson(),
        ),
      ],
    );

    final pushed = await backend.syncManagedVaultPush(
      Uint8List(32),
      Uint8List(32),
      baseUrl: kWebFormalSettingsBaseUrl,
      vaultId: 'vault-123',
      idToken: 'token-1',
    );

    expect(pushed, 0);
    expect(service.requests, isEmpty);
    expect(service.mediaDeletes, <String>['sha-deleted']);
    expect(service.mediaUploads.map((item) => item.remoteId),
        <String>['sha-fresh']);
    expect(
      backend.mediaResults.map((item) => item.success),
      <bool>[true, true],
    );
    expect(
      backend.completedMediaPhases,
      <ManagedVaultV2PushMediaPhase>[
        ManagedVaultV2PushMediaPhase.repairs,
        ManagedVaultV2PushMediaPhase.freshDevice,
      ],
    );
  });

  test('WebNativeAppBackend stops runaway media-only push batches', () async {
    final service = _ManagedVaultPushBridgeService();
    const watchdogLimit = 1024;
    const deleteAction = ManagedVaultV2PushMediaAction(
      kind: ManagedVaultV2PushMediaActionKind.attachmentDelete,
      remoteId: 'sha-stuck',
      sha256: 'sha-stuck',
    );
    final backend = _ManagedVaultPushBridgeBackend(
      appDirProvider: () async => '/opfs/secondloop/vaults/uid-1',
      secureStorage: const FlutterSecureStorage(),
      rustLibInit: () async {},
      webAppService: service,
      batches: List<ManagedVaultV2PushBatch>.generate(
        watchdogLimit,
        (_) => ManagedVaultV2PushBatch(
          hasOps: false,
          opCount: 0,
          request: null,
          mediaActions: const <ManagedVaultV2PushMediaAction>[deleteAction],
          mediaPhase: ManagedVaultV2PushMediaPhase.repairs,
          batchJson: _batchJson(
            mediaPhase: 'repairs',
            mediaActions: <Object?>[deleteAction.toJson()],
          ),
        ),
      ),
    );

    await expectLater(
      backend.syncManagedVaultPush(
        Uint8List(32),
        Uint8List(32),
        baseUrl: kWebFormalSettingsBaseUrl,
        vaultId: 'vault-123',
        idToken: 'token-1',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'managed_vault_push_iteration_limit_exceeded',
        ),
      ),
    );
    expect(service.requests, isEmpty);
    expect(service.mediaDeletes, hasLength(watchdogLimit));
    expect(backend.mediaResults, hasLength(watchdogLimit));
    expect(backend.completedMediaPhases, hasLength(watchdogLimit));
  });
}

String _batchJson({
  String mediaPhase = 'none',
  List<Object?> mediaActions = const <Object?>[],
}) =>
    jsonEncode(<String, Object?>{
      'has_ops': false,
      'device_id': 'device-a',
      'last_pushed_seq': 0,
      'max_seq': 0,
      'op_count': 0,
      'media_phase': mediaPhase,
      'media_actions': mediaActions,
    });

final class _ManagedVaultPushBridgeService extends WebAppService {
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  final List<_RecordedManagedVaultMediaUpload> mediaUploads =
      <_RecordedManagedVaultMediaUpload>[];
  final List<String> mediaDeletes = <String>[];

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription({
    required String idToken,
  }) async {
    return const WebSubscriptionSnapshot(
      state: WebSubscriptionState.entitled,
      canManageSubscription: true,
    );
  }

  @override
  Future<Map<String, Object?>> pushManagedVaultBatch({
    required String idToken,
    required String vaultId,
    required Map<String, Object?> request,
  }) async {
    requests.add(Map<String, Object?>.from(request));
    throw StateError('unexpected_push_request');
  }

  @override
  Future<void> uploadManagedVaultMedia({
    required String idToken,
    required String vaultId,
    required String remoteId,
    required String mimeType,
    required int createdAtMs,
    required List<int> bytes,
    Map<String, String> headers = const <String, String>{},
  }) async {
    mediaUploads.add(
      _RecordedManagedVaultMediaUpload(
        remoteId: remoteId,
        mimeType: mimeType,
        createdAtMs: createdAtMs,
        bytes: List<int>.from(bytes),
      ),
    );
  }

  @override
  Future<void> deleteManagedVaultMedia({
    required String idToken,
    required String vaultId,
    required String remoteId,
  }) async {
    mediaDeletes.add(remoteId);
  }
}

final class _RecordedManagedVaultMediaUpload {
  const _RecordedManagedVaultMediaUpload({
    required this.remoteId,
    required this.mimeType,
    required this.createdAtMs,
    required this.bytes,
  });

  final String remoteId;
  final String mimeType;
  final int createdAtMs;
  final List<int> bytes;
}

final class _RecordedManagedVaultMediaResult {
  const _RecordedManagedVaultMediaResult({
    required this.action,
    required this.success,
    this.errorMessage,
  });

  final ManagedVaultV2PushMediaAction action;
  final bool success;
  final String? errorMessage;
}

final class _ManagedVaultPushBridgeBackend extends WebNativeAppBackend {
  _ManagedVaultPushBridgeBackend({
    required super.appDirProvider,
    required super.secureStorage,
    required super.rustLibInit,
    required super.webAppService,
    required List<ManagedVaultV2PushBatch> batches,
    List<ManagedVaultV2PushMediaUpload> mediaUploads =
        const <ManagedVaultV2PushMediaUpload>[],
  })  : _batches = List<ManagedVaultV2PushBatch>.from(batches),
        _mediaUploads = List<ManagedVaultV2PushMediaUpload>.from(mediaUploads);

  final List<ManagedVaultV2PushBatch> _batches;
  final List<ManagedVaultV2PushMediaUpload> _mediaUploads;
  final List<_RecordedManagedVaultMediaResult> mediaResults =
      <_RecordedManagedVaultMediaResult>[];
  final List<ManagedVaultV2PushMediaPhase> completedMediaPhases =
      <ManagedVaultV2PushMediaPhase>[];

  @override
  Future<ManagedVaultV2PushBatch> prepareManagedVaultV2PushBatch(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) async {
    if (_batches.isEmpty) {
      throw StateError('unexpected_prepare_push_batch');
    }
    return _batches.removeAt(0);
  }

  @override
  Future<ManagedVaultV2PushApplyResult> applyManagedVaultV2PushResponse({
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushBatch batch,
    required Map<String, Object?> response,
  }) async {
    return const ManagedVaultV2PushApplyResult(
      accepted: 0,
      generationId: '',
      remoteLatestGlobalSeq: 0,
    );
  }

  @override
  Future<ManagedVaultV2PushMediaUpload> prepareManagedVaultV2PushMediaUpload({
    required String appDir,
    required Uint8List key,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushMediaAction action,
    required ManagedVaultV2PushMediaPhase mediaPhase,
  }) async {
    if (_mediaUploads.isEmpty) {
      throw StateError('unexpected_prepare_push_media_upload');
    }
    return _mediaUploads.removeAt(0);
  }

  @override
  Future<void> recordManagedVaultV2PushMediaResult({
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushMediaAction action,
    required bool success,
    String? errorMessage,
  }) async {
    mediaResults.add(
      _RecordedManagedVaultMediaResult(
        action: action,
        success: success,
        errorMessage: errorMessage,
      ),
    );
  }

  @override
  Future<void> completeManagedVaultV2PushMediaBatch({
    required String appDir,
    required Uint8List key,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushBatch batch,
  }) async {
    completedMediaPhases.add(batch.mediaPhase);
  }
}
