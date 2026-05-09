import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import 'cloudflare_auth.dart';
import 'manifest.dart';
import 'resource_plan.dart';

typedef DeployResourcesFn = Future<String> Function(
  SelfManagedSetupRequest request,
  String cloudflareToken,
  SelfManagedRuntimeResourcePlan plan,
);

typedef RunHealthCheckFn = Future<void> Function(String apiBaseUrl);

final class SelfManagedRuntimeDeployRunner {
  SelfManagedRuntimeDeployRunner({
    SelfManagedCloudflareAuth? cloudflareAuth,
    DeployResourcesFn? deployResources,
    RunHealthCheckFn? runHealthCheck,
  })  : _cloudflareAuth = cloudflareAuth ?? SelfManagedCloudflareAuth(),
        _deployResources = deployResources ?? _defaultDeployResources,
        _runHealthCheck = runHealthCheck ?? _defaultHealthCheck;

  final SelfManagedCloudflareAuth _cloudflareAuth;
  final DeployResourcesFn _deployResources;
  final RunHealthCheckFn _runHealthCheck;

  Future<SelfManagedSetupResult> run(
    SelfManagedSetupRequest request, {
    required void Function(SelfManagedSetupProgress event) onProgress,
  }) async {
    try {
      if (!request.hasRequiredAiProviderConfig) {
        throw StateError('missing_ai_provider_config');
      }
      onProgress(
        const SelfManagedSetupProgress(
          step: SelfManagedSetupStep.authorizing,
          message: 'authorizing',
        ),
      );
      final cloudflareToken =
          await _cloudflareAuth.authorize(request.cloudflareAccountLabel);
      onProgress(
        const SelfManagedSetupProgress(
          step: SelfManagedSetupStep.deploying,
          message: 'deploying',
        ),
      );
      final apiBaseUrl = await _deployResources(
        request,
        cloudflareToken,
        buildSelfManagedRuntimeResourcePlan(),
      );
      await _runHealthCheck(apiBaseUrl);
      return SelfManagedSetupResult(
        manifest: buildSelfManagedRuntimeManifest(apiBaseUrl: apiBaseUrl),
        authToken: 'runtime-token-${request.provider}',
        capabilityManifestId: 'self-managed-runtime-v1',
      );
    } on StateError catch (error) {
      final code = error.message.toString();
      throw LocalRuntimeHelperException(code, code);
    }
  }
}

Future<String> _defaultDeployResources(
  SelfManagedSetupRequest request,
  String cloudflareToken,
  SelfManagedRuntimeResourcePlan plan,
) async {
  return 'https://${request.cloudflareAccountLabel}.runtime.example/';
}

Future<void> _defaultHealthCheck(String apiBaseUrl) async {
  if (!apiBaseUrl.startsWith('https://')) {
    throw StateError('runtime_health_check_failed');
  }
}
