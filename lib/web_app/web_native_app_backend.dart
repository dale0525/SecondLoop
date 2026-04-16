import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/backend/native_backend.dart';
import 'web_app_service.dart';
import 'web_formal_settings_adapters.dart';

class WebNativeAppBackend extends NativeAppBackend {
  WebNativeAppBackend({
    required super.appDirProvider,
    super.storageScope,
    super.secureStorage,
    super.rustLibInit,
    WebAppService? webAppService,
  })  : _webAppService = webAppService,
        super(
          recoverInterruptedExternalImportBatchesOnInit: false,
        );

  final WebAppService? _webAppService;

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
