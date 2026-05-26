import 'dart:convert';
import 'dart:io';

import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import 'cloudflare_auth.dart';
import 'cloudflare_runtime_resources.dart';
import 'manifest.dart';
import 'resource_plan.dart';

typedef DeployResourcesFn = Future<String> Function(
  SelfManagedSetupRequest request,
  SelfManagedCloudflareAuthorization cloudflareAuthorization,
  SelfManagedRuntimeResourcePlan plan,
);

typedef RunHealthCheckFn = Future<void> Function(String apiBaseUrl);

typedef VerifyModelCapabilitiesFn = Future<ModelCapabilityVerificationResult>
    Function(SelfManagedSetupRequest request, String apiBaseUrl);

typedef PostVerificationJsonFn = Future<Map<String, Object?>> Function(
  Uri uri,
  Map<String, Object?> body,
);

final class SelfManagedRuntimeDeployRunner {
  SelfManagedRuntimeDeployRunner({
    SelfManagedCloudflareAuth? cloudflareAuth,
    DeployResourcesFn? deployResources,
    RunHealthCheckFn? runHealthCheck,
    VerifyModelCapabilitiesFn? verifyModelCapabilities,
    PostVerificationJsonFn? postVerificationJson,
  })  : _cloudflareAuth = cloudflareAuth ?? SelfManagedCloudflareAuth(),
        _deployResources = deployResources ?? _defaultDeployResources,
        _runHealthCheck = runHealthCheck ?? _defaultHealthCheck,
        _verifyModelCapabilities = verifyModelCapabilities ??
            ((request, apiBaseUrl) => _defaultVerifyModelCapabilities(
                  request,
                  apiBaseUrl,
                  postJson: postVerificationJson ?? _postVerificationJson,
                ));

  final SelfManagedCloudflareAuth _cloudflareAuth;
  final DeployResourcesFn _deployResources;
  final RunHealthCheckFn _runHealthCheck;
  final VerifyModelCapabilitiesFn _verifyModelCapabilities;

  Future<SelfManagedSetupResult> run(
    SelfManagedSetupRequest request, {
    required void Function(SelfManagedSetupProgress event) onProgress,
  }) async {
    try {
      final missingCloudflare =
          request.firstMissingCloudflareAuthorizationField;
      if (missingCloudflare != null) {
        throw StateError(missingCloudflare);
      }
      if (!request.hasRequiredAiProviderConfig) {
        throw StateError('missing_ai_provider_config');
      }
      onProgress(
        const SelfManagedSetupProgress(
          step: SelfManagedSetupStep.authorizing,
          message: 'authorizing',
        ),
      );
      final cloudflareAuthorization = request.usesManualCloudflareCredentials
          ? SelfManagedCloudflareAuthorization(
              accessToken: request.cloudflareApiToken.trim(),
              accountId: request.cloudflareDeploymentAccountId,
              accountName: request.cloudflareDeploymentAccountId,
            )
          : await _cloudflareAuth.authorize(request.cloudflareAccountLabel);
      onProgress(
        const SelfManagedSetupProgress(
          step: SelfManagedSetupStep.deploying,
          message: 'deploying',
        ),
      );
      final apiBaseUrl = await _deployResources(
        request,
        cloudflareAuthorization,
        buildSelfManagedRuntimeResourcePlan(),
      );
      await _runHealthCheck(apiBaseUrl);
      onProgress(
        const SelfManagedSetupProgress(
          step: SelfManagedSetupStep.verifying,
          message: 'verifying_model_capabilities',
        ),
      );
      final verification = await _verifyModelCapabilities(request, apiBaseUrl);
      if (!verification.ok) {
        final code = verification.firstFailureCode ??
            'model_capability_verification_failed';
        throw LocalRuntimeHelperException(code, code);
      }
      return SelfManagedSetupResult(
        manifest: buildSelfManagedRuntimeManifest(apiBaseUrl: apiBaseUrl),
        authToken: 'runtime-token-${request.provider}',
        capabilityManifestId: 'self-managed-runtime-v1',
        verification: verification,
      );
    } on StateError catch (error) {
      final code = error.message.toString();
      throw LocalRuntimeHelperException(code, code);
    }
  }
}

Future<String> _defaultDeployResources(
  SelfManagedSetupRequest request,
  SelfManagedCloudflareAuthorization cloudflareAuthorization,
  SelfManagedRuntimeResourcePlan plan,
) async {
  if (!cloudflareAuthorization.canManageResources) {
    return 'https://${request.cloudflareDeploymentAccountId}.runtime.example/';
  }
  final client = CloudflareRuntimeResourcesClient(
    accountId: cloudflareAuthorization.accountId,
    apiToken: cloudflareAuthorization.accessToken,
  );
  return client.deployLocalQaRuntime(request, plan);
}

Future<void> _defaultHealthCheck(String apiBaseUrl) async {
  if (!apiBaseUrl.startsWith('https://')) {
    throw StateError('runtime_health_check_failed');
  }
}

Future<ModelCapabilityVerificationResult> _defaultVerifyModelCapabilities(
    SelfManagedSetupRequest request, String apiBaseUrl,
    {required PostVerificationJsonFn postJson}) async {
  try {
    final baseUri = Uri.parse(apiBaseUrl.trim());
    final route = baseUri.replace(
      path: _joinUriPath(baseUri.path, 'v1/runtime/model/verify-capabilities'),
      query: null,
      fragment: null,
    );
    final decoded = await postJson(route, <String, Object?>{
      'vault_id': request.cloudflareDeploymentAccountId,
      'runtime_mode': 'self_managed',
      'provider': request.provider,
    });
    return ModelCapabilityVerificationResult.fromJson(
      decoded,
    );
  } on FormatException {
    return _verificationTransportFailure();
  } on HttpException {
    return _verificationTransportFailure();
  } on SocketException {
    return _verificationTransportFailure();
  }
}

Future<Map<String, Object?>> _postVerificationJson(
  Uri uri,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  try {
    final httpRequest = await client.postUrl(uri);
    httpRequest.headers.contentType = ContentType.json;
    httpRequest.write(jsonEncode(body));
    final response = await httpRequest.close();
    final rawBody = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      throw const FormatException('verification response is not an object');
    }
    return decoded.map((key, value) => MapEntry('$key', value as Object?));
  } finally {
    client.close(force: true);
  }
}

String _joinUriPath(String basePath, String routePath) {
  final normalizedBase = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  return '$normalizedBase/$routePath';
}

ModelCapabilityVerificationResult _verificationTransportFailure() {
  return const ModelCapabilityVerificationResult(
    ok: false,
    checks: [
      ModelCapabilityCheckResult(
        code: 'model_capability_verification',
        passed: false,
        failureCode: 'model_capability_verification_failed',
      ),
    ],
  );
}
