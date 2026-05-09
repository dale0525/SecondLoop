import 'runtime_test_client.dart';
import 'runtime_test_models.dart';
import 'secretary_runtime_client.dart';

final class RuntimeTestDriver {
  RuntimeTestDriver({
    RuntimeTestClient? runtimeTestClient,
    SecretaryRuntimeClient? runtimeClient,
  })  : _runtimeTestClient = runtimeTestClient ?? RuntimeTestClient(),
        _runtimeClient = runtimeClient ?? SecretaryRuntimeClient();

  final RuntimeTestClient _runtimeTestClient;
  final SecretaryRuntimeClient _runtimeClient;

  Future<RuntimeTestBootstrapResult> bootstrapRuntime({String? vaultId}) {
    return _runtimeTestClient.bootstrap(vaultId: vaultId);
  }

  Future<void> seedStandardFixture(String vaultId) {
    return _runtimeTestClient.injectFixtures(
      vaultId: vaultId,
      records: [
        const RuntimeTestFixtureRecord(
          kind: 'task',
          id: 'task-1',
          fields: {
            'title': 'Complete weekly review',
            'status': 'open',
          },
        ).toJson(),
        const RuntimeTestFixtureRecord(
          kind: 'task',
          id: 'task-2',
          fields: {
            'title': 'Prepare deployment notes',
            'status': 'open',
          },
        ).toJson(),
      ],
    );
  }

  Future<void> configureFixedPlanSimulation(String vaultId) {
    return _runtimeTestClient.configureProviderSimulation(
      vaultId: vaultId,
      provider: 'openai',
      purpose: 'plan_generation',
      simulation: const RuntimeProviderSimulationConfig(
        mode: 'fixed_response',
        output: {
          'output_text': 'fixed-plan-output',
        },
      ).toJson(),
    );
  }

  Future<void> requestPlan(String vaultId) {
    return _runtimeClient.requestPlanRefresh(vaultId);
  }

  Future<RuntimeTestRunResult> sendRuntimeMessage({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    return _runtimeTestClient.sendMessage(
      vaultId: vaultId,
      conversationId: conversationId,
      message: message,
    );
  }

  Future<RuntimeTestSnapshot> snapshot(String vaultId) {
    return _runtimeTestClient.snapshot(vaultId);
  }

  Future<RuntimeTestStateDiff> diffSnapshots({
    required String beforeLabel,
    required String afterLabel,
  }) {
    return _runtimeTestClient.fetchStateDiff(
      beforeLabel: beforeLabel,
      afterLabel: afterLabel,
    );
  }
}
