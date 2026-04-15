import 'web_local_runtime_recovery_base.dart';

WebLocalRuntimeRecovery createWebLocalRuntimeRecovery() =>
    const _StubWebLocalRuntimeRecovery();

final class _StubWebLocalRuntimeRecovery implements WebLocalRuntimeRecovery {
  const _StubWebLocalRuntimeRecovery();

  @override
  bool hasAttemptedReset({required String uid}) => false;

  @override
  void markResetAttempted({required String uid}) {}

  @override
  void clearResetAttempted({required String uid}) {}

  @override
  Future<void> reloadPage() async {}
}
