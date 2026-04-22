import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/backend/native_backend.dart';
import '../src/rust/api/web_sync.dart' as rust_web_sync;
import 'web_app_service.dart';
import 'web_formal_settings_adapters.dart';

class ManagedVaultV2PullState {
  const ManagedVaultV2PullState({
    required this.generationId,
    required this.lastAppliedGlobalSeq,
  });

  final String? generationId;
  final int lastAppliedGlobalSeq;
}

class ManagedVaultV2PullApplyResult extends ManagedVaultV2PullState {
  const ManagedVaultV2PullApplyResult({
    required super.generationId,
    required super.lastAppliedGlobalSeq,
    required this.appliedCount,
    required this.remoteLatestGlobalSeq,
    required this.hasMore,
  });

  final int appliedCount;
  final int remoteLatestGlobalSeq;
  final bool hasMore;
}

class WebNativeAppBackend extends NativeAppBackend {
  WebNativeAppBackend({
    required AppDirProvider appDirProvider,
    super.storageScope,
    super.secureStorage,
    super.rustLibInit,
    WebAppService? webAppService,
  })  : _appDirProvider = appDirProvider,
        _webAppService = webAppService,
        super(
          appDirProvider: appDirProvider,
          recoverInterruptedExternalImportBatchesOnInit: false,
        );

  final AppDirProvider _appDirProvider;
  final WebAppService? _webAppService;
  Future<String>? _appDirFuture;

  Future<String> _resolveAppDir() => _appDirFuture ??= _appDirProvider();

  bool _shouldBridgeCloudGateway(String gatewayBaseUrl) {
    return _webAppService != null && isWebFormalSettingsBaseUrl(gatewayBaseUrl);
  }

  factory WebNativeAppBackend.withDefaults({
    required AppDirProvider appDirProvider,
    String? storageScope,
    WebAppService? webAppService,
  }) {
    return WebNativeAppBackend(
      appDirProvider: appDirProvider,
      storageScope: storageScope,
      secureStorage: const FlutterSecureStorage(),
      webAppService: webAppService,
    );
  }

  ManagedVaultV2PullState readManagedVaultV2PullState({
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) {
    final decoded = jsonDecode(
      rust_web_sync.syncManagedVaultReadWebPullState(
        appDir: appDir,
        baseUrl: baseUrl,
        vaultId: vaultId,
      ),
    );
    if (decoded is! Map) {
      throw const FormatException('invalid_managed_vault_pull_state');
    }
    return ManagedVaultV2PullState(
      generationId: '${decoded['generation_id'] ?? ''}'.trim().isEmpty
          ? null
          : '${decoded['generation_id']}',
      lastAppliedGlobalSeq:
          (decoded['last_applied_global_seq'] as num?)?.toInt() ?? 0,
    );
  }

  ManagedVaultV2PullApplyResult applyManagedVaultV2PullPage(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required WebManagedVaultPullPage page,
  }) {
    final decoded = jsonDecode(
      rust_web_sync.syncManagedVaultApplyWebPullPage(
        appDir: appDir,
        key: key,
        syncKey: syncKey,
        baseUrl: baseUrl,
        vaultId: vaultId,
        responseJson: jsonEncode(<String, Object?>{
          'generation_id': page.generationId,
          'remote_latest_global_seq': page.remoteLatestGlobalSeq,
          'has_more': page.hasMore,
          'ops': page.ops
              .map((item) => <String, Object?>{
                    'global_seq': item.globalSeq,
                    'device_id': item.deviceId,
                    'seq': item.seq,
                    'op_id': item.opId,
                    'client_op_id': item.clientOpId,
                    'ciphertext_b64': item.ciphertextB64,
                  })
              .toList(growable: false),
        }),
      ),
    );
    if (decoded is! Map) {
      throw const FormatException('invalid_managed_vault_pull_apply_result');
    }
    return ManagedVaultV2PullApplyResult(
      generationId: '${decoded['generation_id'] ?? ''}'.trim().isEmpty
          ? null
          : '${decoded['generation_id']}',
      lastAppliedGlobalSeq:
          (decoded['last_applied_global_seq'] as num?)?.toInt() ?? 0,
      appliedCount: (decoded['applied_count'] as num?)?.toInt() ?? 0,
      remoteLatestGlobalSeq:
          (decoded['remote_latest_global_seq'] as num?)?.toInt() ?? 0,
      hasMore: decoded['has_more'] == true,
    );
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final webAppService = _webAppService;
    if (webAppService == null) {
      return super.syncManagedVaultPull(
        key,
        syncKey,
        baseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
      );
    }

    final appDir = await _resolveAppDir();
    var state = readManagedVaultV2PullState(
      appDir: appDir,
      baseUrl: baseUrl,
      vaultId: vaultId,
    );
    var totalApplied = 0;
    while (true) {
      final page = await webAppService.fetchManagedVaultPullPage(
        idToken: idToken,
        vaultId: vaultId,
        afterGlobalSeq: state.lastAppliedGlobalSeq,
      );
      final result = applyManagedVaultV2PullPage(
        key,
        syncKey,
        appDir: appDir,
        baseUrl: baseUrl,
        vaultId: vaultId,
        page: page,
      );
      totalApplied += result.appliedCount;
      state = result;
      if (!page.hasMore) {
        return totalApplied;
      }
    }
  }

  @override
  Stream<String> syncManagedVaultPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pulled = await syncManagedVaultPull(
      key,
      syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
    yield '{"type":"result","count":$pulled}';
  }

  @override
  Stream<String> syncManagedVaultPushOpsOnlyProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pushed = await syncManagedVaultPushOpsOnly(
      key,
      syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
    yield '{"type":"result","count":$pushed}';
  }

  @override
  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) async {
    if (!_shouldBridgeCloudGateway(gatewayBaseUrl)) {
      return super.fetchTaskPriorityAiAssessmentsCloudGateway(
        key,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        cacheScopeKey: cacheScopeKey,
      );
    }

    final json = await _webAppService!.fetchTaskPriorityAssessments(
      idToken: idToken,
      scope: cacheScopeKey,
    );
    return jsonEncode(json);
  }

  @override
  Future<void> upsertTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    required String payloadJson,
  }) async {
    if (!_shouldBridgeCloudGateway(gatewayBaseUrl)) {
      return super.upsertTaskPriorityAiAssessmentsCloudGateway(
        key,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        cacheScopeKey: cacheScopeKey,
        payloadJson: payloadJson,
      );
    }

    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) {
      throw const FormatException('invalid_task_priority_assessment_payload');
    }

    await _webAppService!.upsertTaskPriorityAssessments(
      idToken: idToken,
      payload: decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}
