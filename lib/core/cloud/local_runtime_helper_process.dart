import 'self_managed_setup_models.dart';
import 'local_runtime_helper_process_runner.dart';

typedef LocalRuntimeSetupRunner = Future<SelfManagedSetupResult> Function(
  SelfManagedSetupRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
);

typedef LocalRuntimeUninstallRunner = Future<SelfManagedRuntimeUninstallResult>
    Function(
  SelfManagedRuntimeUninstallRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
);

typedef LocalRuntimeCloudflareAuthorizationRunner
    = Future<SelfManagedCloudflareAuthorizationResult> Function(
  String accountLabel,
  void Function(SelfManagedSetupProgress event) onProgress,
);

class LocalRuntimeHelperException implements Exception {
  const LocalRuntimeHelperException(this.code, this.message);

  final String code;
  final String message;
}

final class LocalRuntimeHelperProcess {
  LocalRuntimeHelperProcess({
    LocalRuntimeSetupRunner? runner,
    LocalRuntimeCloudflareAuthorizationRunner? cloudflareAuthorizationRunner,
    LocalRuntimeUninstallRunner? uninstallRunner,
  })  : _runner = runner ?? _defaultRunner,
        _cloudflareAuthorizationRunner =
            cloudflareAuthorizationRunner ?? _defaultCloudflareAuthorization,
        _uninstallRunner = uninstallRunner ?? _defaultUninstallRunner;

  final LocalRuntimeSetupRunner _runner;
  final LocalRuntimeCloudflareAuthorizationRunner
      _cloudflareAuthorizationRunner;
  final LocalRuntimeUninstallRunner _uninstallRunner;

  Future<SelfManagedSetupResult> runSetup(
    SelfManagedSetupRequest request, {
    required void Function(SelfManagedSetupProgress event) onProgress,
  }) {
    return _runner(request, onProgress);
  }

  Future<SelfManagedCloudflareAuthorizationResult> runCloudflareAuthorization(
    String accountLabel, {
    required void Function(SelfManagedSetupProgress event) onProgress,
  }) {
    return _cloudflareAuthorizationRunner(accountLabel, onProgress);
  }

  Future<SelfManagedRuntimeUninstallResult> runUninstall(
    SelfManagedRuntimeUninstallRequest request, {
    required void Function(SelfManagedSetupProgress event) onProgress,
  }) {
    return _uninstallRunner(request, onProgress);
  }
}

Future<SelfManagedSetupResult> _defaultRunner(
  SelfManagedSetupRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  return runLocalRuntimeSetupHelper(request, onProgress);
}

Future<SelfManagedCloudflareAuthorizationResult>
    _defaultCloudflareAuthorization(
  String accountLabel,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  return runLocalRuntimeCloudflareAuthorizationHelper(accountLabel, onProgress);
}

Future<SelfManagedRuntimeUninstallResult> _defaultUninstallRunner(
  SelfManagedRuntimeUninstallRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  return runLocalRuntimeUninstallHelper(request, onProgress);
}
