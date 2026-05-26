import 'local_runtime_helper_process.dart';
import 'self_managed_setup_models.dart';

Future<SelfManagedSetupResult> runLocalRuntimeSetupHelper(
  SelfManagedSetupRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  throw const LocalRuntimeHelperException(
    'self_managed_helper_unavailable',
    'Self-managed runtime helper is not available on this platform.',
  );
}

Future<SelfManagedCloudflareAuthorizationResult>
    runLocalRuntimeCloudflareAuthorizationHelper(
  String accountLabel,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  throw const LocalRuntimeHelperException(
    'tool_unavailable:cloudflare_oauth',
    'Cloudflare OAuth handoff is not available on this platform.',
  );
}

Future<SelfManagedRuntimeUninstallResult> runLocalRuntimeUninstallHelper(
  SelfManagedRuntimeUninstallRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  throw const LocalRuntimeHelperException(
    'self_managed_uninstall_helper_unavailable',
    'Self-managed runtime uninstall helper is not available on this platform.',
  );
}
