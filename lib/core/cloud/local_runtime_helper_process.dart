import 'self_managed_setup_models.dart';

typedef LocalRuntimeSetupRunner = Future<SelfManagedSetupResult> Function(
  SelfManagedSetupRequest request,
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
  }) : _runner = runner ?? _defaultRunner;

  final LocalRuntimeSetupRunner _runner;

  Future<SelfManagedSetupResult> runSetup(
    SelfManagedSetupRequest request, {
    required void Function(SelfManagedSetupProgress event) onProgress,
  }) {
    return _runner(request, onProgress);
  }
}

Future<SelfManagedSetupResult> _defaultRunner(
  SelfManagedSetupRequest request,
  void Function(SelfManagedSetupProgress event) onProgress,
) async {
  throw const LocalRuntimeHelperException(
    'self_managed_helper_unavailable',
    'Self-managed runtime helper is not available.',
  );
}
