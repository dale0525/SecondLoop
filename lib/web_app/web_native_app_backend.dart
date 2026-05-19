import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/backend/native_backend.dart';
import 'web_app_service.dart';
import 'web_formal_settings_adapters.dart';

part 'web_native_app_backend_managed_vault_push.dart';

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
    this.retryRequired = false,
    this.recoveryReason,
  });

  final int appliedCount;
  final int remoteLatestGlobalSeq;
  final bool hasMore;
  final bool retryRequired;
  final String? recoveryReason;
}

class ManagedVaultV2PushBatch {
  const ManagedVaultV2PushBatch({
    required this.hasOps,
    required this.opCount,
    required this.request,
    required this.batchJson,
    this.mediaActions = const <ManagedVaultV2PushMediaAction>[],
    this.mediaPhase = ManagedVaultV2PushMediaPhase.none,
  });

  final bool hasOps;
  final int opCount;
  final Map<String, Object?>? request;
  final String batchJson;
  final List<ManagedVaultV2PushMediaAction> mediaActions;
  final ManagedVaultV2PushMediaPhase mediaPhase;
}

class ManagedVaultV2PushApplyResult {
  const ManagedVaultV2PushApplyResult({
    required this.accepted,
    required this.generationId,
    required this.remoteLatestGlobalSeq,
  });

  final int accepted;
  final String generationId;
  final int remoteLatestGlobalSeq;
}

UnsupportedError _retiredWebNativeRuntimeFeature(String feature) {
  return UnsupportedError('runtime_first_native_runtime_removed:$feature');
}

class WebNativeAppBackend extends NativeAppBackend
    with _WebNativeManagedVaultPushBridge {
  WebNativeAppBackend({
    required AppDirProvider appDirProvider,
    super.storageScope,
    super.secureStorage,
    super.rustLibInit,
    WebAppService? webAppService,
  })  : _appDirProvider = appDirProvider,
        _webAppService = webAppService,
        super(appDirProvider: appDirProvider);

  final AppDirProvider _appDirProvider;
  final WebAppService? _webAppService;
  Future<String>? _appDirFuture;

  @override
  Future<String> _resolveAppDir() => _appDirFuture ??= _appDirProvider();

  bool _shouldBridgeCloudGateway(String gatewayBaseUrl) {
    return _webAppService != null && isWebFormalSettingsBaseUrl(gatewayBaseUrl);
  }

  bool _shouldBridgeManagedVault(String baseUrl) {
    return _webAppService != null && isWebManagedVaultBridgeBaseUrl(baseUrl);
  }

  List<Map<String, String>> _encodeChatMessages(List<dynamic> messages) {
    return messages
        .map(
          (message) => <String, String>{
            'role': '${message.role}',
            'content': '${message.content}',
          },
        )
        .toList(growable: false);
  }

  Future<String> _sendCloudChatRequest(
    Uint8List key,
    String conversationId, {
    required String question,
    required String idToken,
  }) async {
    await insertMessage(
      key,
      conversationId,
      role: 'user',
      content: question,
    );
    final history = await listMessages(key, conversationId);
    final reply = await _webAppService!.sendChat(
      idToken: idToken,
      messages: _encodeChatMessages(history),
    );
    await insertMessage(
      key,
      conversationId,
      role: 'assistant',
      content: reply,
    );
    return reply;
  }

  Future<String> _sendPromptOnlyCloudChat({
    required String prompt,
    required String idToken,
  }) {
    return _webAppService!.sendChat(
      idToken: idToken,
      messages: <Map<String, String>>[
        <String, String>{'role': 'user', 'content': prompt},
      ],
    );
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

  Future<ManagedVaultV2PullState> readManagedVaultV2PullState({
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) async {
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultReadWebPullState',
    );
  }

  Future<ManagedVaultV2PullApplyResult> applyManagedVaultV2PullPage(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required WebManagedVaultPullPage page,
  }) async {
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultApplyWebPullPage',
    );
  }

  Future<ManagedVaultV2PullState> recoverManagedVaultV2PullState(
    Uint8List key, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) async {
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultRecoverWebPullState',
    );
  }

  Future<void> finalizeManagedVaultV2Pull(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required int appliedOps,
  }) async {
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultFinalizeWebPull',
    );
  }

  bool _isManagedVaultPullResetRequired(Object error) {
    return error is WebAppHttpException &&
        error.statusCode == 409 &&
        error.code == 'reset_required';
  }

  Map<String, Object?> _decodeManagedVaultErrorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } on FormatException {
      // Fall through to the empty payload when the upstream body is not JSON.
    }
    return const <String, Object?>{};
  }

  StateError _persistentManagedVaultPullRecoveryError({
    required String reason,
    required ManagedVaultV2PullState state,
    WebManagedVaultPullPage? page,
    WebAppHttpException? error,
  }) {
    switch (reason) {
      case 'reset_required':
        final body = error == null
            ? const <String, Object?>{}
            : _decodeManagedVaultErrorBody(error.body);
        return StateError(
          'managed-vault v2 pull reset_required persisted after local rebuild: '
          'reason=${body['reason']} '
          'remote_generation_id=${body['remote_generation_id']} '
          'remote_latest_global_seq=${body['remote_latest_global_seq']}',
        );
      case 'generation_mismatch':
        return StateError(
          'managed-vault v2 pull generation mismatch persisted after local rebuild: '
          'local_generation_id=${state.generationId} '
          'remote_generation_id=${page?.generationId}',
        );
      case 'empty_remote_state':
        return StateError(
          'managed-vault v2 pull empty_remote_state persisted after local rebuild: '
          'local_generation_id=${state.generationId} '
          'after_global_seq=${state.lastAppliedGlobalSeq}',
        );
      case 'non_contiguous':
        return StateError(
          'managed-vault v2 pull non-contiguous page persisted after local rebuild: '
          'after_global_seq=${state.lastAppliedGlobalSeq}',
        );
      default:
        return StateError('managed_vault_pull_recovery_persisted:$reason');
    }
  }

  Future<int> _syncManagedVaultPullThroughWebAppService(
    WebAppService webAppService,
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    void Function(int done, int total)? onProgress,
  }) async {
    final appDir = await _resolveAppDir();
    var state = await readManagedVaultV2PullState(
      appDir: appDir,
      baseUrl: baseUrl,
      vaultId: vaultId,
    );
    var totalApplied = 0;
    var resetRecovered = false;
    var emptyRemoteStateRecovered = false;
    var generationRecovered = false;
    var nonContiguousRecovered = false;
    var progressBaseline = state.lastAppliedGlobalSeq;
    int? totalTarget;
    var progressResetPending = false;
    while (true) {
      late final WebManagedVaultPullPage page;
      try {
        page = await webAppService.fetchManagedVaultPullPage(
          idToken: idToken,
          vaultId: vaultId,
          afterGlobalSeq: state.lastAppliedGlobalSeq,
        );
      } on WebAppHttpException catch (error) {
        if (!_isManagedVaultPullResetRequired(error)) {
          rethrow;
        }
        if (resetRecovered) {
          throw _persistentManagedVaultPullRecoveryError(
            reason: 'reset_required',
            state: state,
            error: error,
          );
        }
        state = await recoverManagedVaultV2PullState(
          key,
          appDir: appDir,
          baseUrl: baseUrl,
          vaultId: vaultId,
        );
        totalApplied = 0;
        progressBaseline = state.lastAppliedGlobalSeq;
        totalTarget = null;
        resetRecovered = true;
        progressResetPending = true;
        continue;
      }
      final result = await applyManagedVaultV2PullPage(
        key,
        syncKey,
        appDir: appDir,
        baseUrl: baseUrl,
        vaultId: vaultId,
        page: page,
      );
      if (result.retryRequired) {
        switch (result.recoveryReason) {
          case 'empty_remote_state':
            if (emptyRemoteStateRecovered) {
              throw _persistentManagedVaultPullRecoveryError(
                reason: 'empty_remote_state',
                state: state,
                page: page,
              );
            }
            emptyRemoteStateRecovered = true;
            break;
          case 'generation_mismatch':
            if (generationRecovered) {
              throw _persistentManagedVaultPullRecoveryError(
                reason: 'generation_mismatch',
                state: state,
                page: page,
              );
            }
            generationRecovered = true;
            break;
          case 'non_contiguous':
            if (nonContiguousRecovered) {
              throw _persistentManagedVaultPullRecoveryError(
                reason: 'non_contiguous',
                state: state,
                page: page,
              );
            }
            nonContiguousRecovered = true;
            break;
          case null:
            throw StateError(
              'managed_vault_pull_unexpected_retry_reason:null',
            );
          default:
            throw StateError(
              'managed_vault_pull_unexpected_retry_reason:${result.recoveryReason}',
            );
        }
        state = result;
        totalApplied = 0;
        progressBaseline = state.lastAppliedGlobalSeq;
        totalTarget = null;
        progressResetPending = true;
        continue;
      }
      totalApplied += result.appliedCount;
      state = result;

      final effectiveTotalTarget = totalTarget ??=
          (result.remoteLatestGlobalSeq - progressBaseline)
              .clamp(0, 1 << 31)
              .toInt();
      if (progressResetPending && effectiveTotalTarget > 0) {
        onProgress?.call(0, effectiveTotalTarget);
        progressResetPending = false;
      }
      if (effectiveTotalTarget > 0) {
        final done = (state.lastAppliedGlobalSeq - progressBaseline)
            .clamp(0, effectiveTotalTarget)
            .toInt();
        onProgress?.call(done, effectiveTotalTarget);
      }

      if (!result.hasMore) {
        await finalizeManagedVaultV2Pull(
          key,
          syncKey,
          appDir: appDir,
          baseUrl: baseUrl,
          vaultId: vaultId,
          idToken: idToken,
          appliedOps: totalApplied,
        );
        return totalApplied;
      }
    }
  }

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async* {
    if (!_shouldBridgeCloudGateway(gatewayBaseUrl)) {
      yield* super.askAiStreamCloudGateway(
        key,
        conversationId,
        question: question,
        topK: topK,
        thisThreadOnly: thisThreadOnly,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        modelName: modelName,
      );
      return;
    }

    yield await _sendCloudChatRequest(
      key,
      conversationId,
      question: question,
      idToken: idToken,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayWithEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) async* {
    if (!_shouldBridgeCloudGateway(gatewayBaseUrl)) {
      yield* super.askAiStreamCloudGatewayWithEmbeddings(
        key,
        conversationId,
        question: question,
        topK: topK,
        thisThreadOnly: thisThreadOnly,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        modelName: modelName,
        embeddingsModelName: embeddingsModelName,
      );
      return;
    }

    yield await _sendCloudChatRequest(
      key,
      conversationId,
      question: question,
      idToken: idToken,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    return askAiStreamCloudGateway(
      key,
      conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayWithEmbeddingsTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) {
    return askAiStreamCloudGatewayWithEmbeddings(
      key,
      conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: modelName,
      embeddingsModelName: embeddingsModelName,
    );
  }

  @override
  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    if (!_shouldBridgeCloudGateway(gatewayBaseUrl)) {
      return super.taskPriorityRerankAiCloudGateway(
        key,
        prompt: prompt,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        modelName: modelName,
      );
    }

    return _sendPromptOnlyCloudChat(
      prompt: prompt,
      idToken: idToken,
    );
  }

  @override
  Future<String> todoFollowupRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    if (!_shouldBridgeCloudGateway(gatewayBaseUrl)) {
      return super.todoFollowupRerankAiCloudGateway(
        key,
        prompt: prompt,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        modelName: modelName,
      );
    }

    return _sendPromptOnlyCloudChat(
      prompt: prompt,
      idToken: idToken,
    );
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final webAppService = _webAppService;
    if (!_shouldBridgeManagedVault(baseUrl)) {
      return super.syncManagedVaultPush(
        key,
        syncKey,
        baseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
      );
    }

    return _syncManagedVaultPushThroughWebAppService(
      webAppService!,
      key,
      syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
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
    if (!_shouldBridgeManagedVault(baseUrl)) {
      return super.syncManagedVaultPull(
        key,
        syncKey,
        baseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
      );
    }

    return _syncManagedVaultPullThroughWebAppService(
      webAppService!,
      key,
      syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
  }

  @override
  Stream<String> syncManagedVaultPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    final webAppService = _webAppService;
    if (_shouldBridgeManagedVault(baseUrl)) {
      final controller = StreamController<String>();
      unawaited(() async {
        try {
          final pulled = await _syncManagedVaultPullThroughWebAppService(
            webAppService!,
            key,
            syncKey,
            baseUrl: baseUrl,
            vaultId: vaultId,
            idToken: idToken,
            onProgress: (done, total) {
              controller.add(
                jsonEncode(<String, Object?>{
                  'type': 'progress',
                  'done': done,
                  'total': total,
                }),
              );
            },
          );
          controller.add(
            jsonEncode(<String, Object?>{
              'type': 'result',
              'count': pulled,
            }),
          );
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        } finally {
          await controller.close();
        }
      }());
      yield* controller.stream;
      return;
    }

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
  Stream<String> syncManagedVaultPushProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    yield '{"type":"progress","done":0,"total":0}';
    final pushed = await syncManagedVaultPush(
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
