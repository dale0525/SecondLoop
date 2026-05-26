import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import 'cloudflare_auth.dart';
import 'cloudflare_runtime_resources.dart';
import 'resource_plan.dart';

typedef UninstallResourcesFn = Future<SelfManagedRuntimeUninstallResult>
    Function(
  SelfManagedRuntimeUninstallRequest request,
  SelfManagedCloudflareAuthorization cloudflareAuthorization,
  SelfManagedRuntimeResourcePlan plan,
);

final class SelfManagedRuntimeUninstallRunner {
  SelfManagedRuntimeUninstallRunner({
    SelfManagedCloudflareAuth? cloudflareAuth,
    UninstallResourcesFn? uninstallResources,
  })  : _cloudflareAuth = cloudflareAuth ?? SelfManagedCloudflareAuth(),
        _uninstallResources = uninstallResources ?? _defaultUninstallResources;

  final SelfManagedCloudflareAuth _cloudflareAuth;
  final UninstallResourcesFn _uninstallResources;

  Future<SelfManagedRuntimeUninstallResult> run(
    SelfManagedRuntimeUninstallRequest request, {
    required void Function(SelfManagedSetupProgress event) onProgress,
  }) async {
    try {
      final missingCloudflare =
          request.firstMissingCloudflareAuthorizationField;
      if (missingCloudflare != null) {
        throw StateError(missingCloudflare);
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
          step: SelfManagedSetupStep.uninstalling,
          message: 'uninstalling',
        ),
      );
      final result = await _uninstallResources(
        request,
        cloudflareAuthorization,
        buildSelfManagedRuntimeResourcePlan(),
      );
      onProgress(
        const SelfManagedSetupProgress(
          step: SelfManagedSetupStep.uninstalled,
          message: 'uninstalled',
        ),
      );
      return result;
    } on StateError catch (error) {
      final code = error.message.toString();
      throw LocalRuntimeHelperException(code, code);
    }
  }
}

Future<SelfManagedRuntimeUninstallResult> _defaultUninstallResources(
  SelfManagedRuntimeUninstallRequest request,
  SelfManagedCloudflareAuthorization cloudflareAuthorization,
  SelfManagedRuntimeResourcePlan plan,
) async {
  if (!cloudflareAuthorization.canManageResources) {
    return SelfManagedRuntimeUninstallResult(
      ok: true,
      runtimeMode: 'self_managed',
      cloudflareAccountId: request.cloudflareDeploymentAccountId,
      removedWorkers: plan.workerNames,
      removedBindings: plan.bindings,
      removedSecrets: plan.secrets,
    );
  }
  final client = CloudflareRuntimeResourcesClient(
    accountId: cloudflareAuthorization.accountId,
    apiToken: cloudflareAuthorization.accessToken,
  );
  return client.uninstallLocalQaRuntime(request, plan);
}
