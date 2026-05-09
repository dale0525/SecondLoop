import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_test_models.dart';

void main() {
  test('fixture records serialize with flattened fields', () {
    const record = RuntimeTestFixtureRecord(
      kind: 'task',
      id: 'task-1',
      fields: {
        'title': 'Submit review',
        'status': 'open',
      },
    );

    expect(record.toJson(), {
      'kind': 'task',
      'id': 'task-1',
      'title': 'Submit review',
      'status': 'open',
    });
  });

  test('provider simulation config serializes optional output', () {
    const config = RuntimeProviderSimulationConfig(
      mode: 'fixed_response',
      output: {
        'output_text': 'fixed',
      },
    );

    expect(config.toJson(), {
      'mode': 'fixed_response',
      'output': {
        'output_text': 'fixed',
      },
    });
  });

  test('snapshot parses nested agent and provider state', () {
    final snapshot = RuntimeTestSnapshot.fromJson(const {
      'agent_state': {
        'approvals': [
          {'id': 'approval-1'},
        ],
      },
      'provider_simulation': {
        'mode': 'fixed_response',
      },
    });

    expect(snapshot.agentState['approvals'], isNotEmpty);
    expect(snapshot.providerSimulation['mode'], 'fixed_response');
  });

  test('bootstrap result parses manifest and conversation seed', () {
    final bootstrap = RuntimeTestBootstrapResult.fromJson(const {
      'vault_id': 'vault-1',
      'runtime_token': 'runtime-test-token',
      'conversation_seed': 'conversation-vault-1-seed',
      'manifest': {
        'runtime_mode': 'self_managed',
      },
    });

    expect(bootstrap.vaultId, 'vault-1');
    expect(bootstrap.runtimeToken, 'runtime-test-token');
    expect(bootstrap.manifest['runtime_mode'], 'self_managed');
  });

  test('state diff captures changed snapshot labels and paths', () {
    final diff = RuntimeTestStateDiff.fromJson(const {
      'schema_version': runtimeTestContractSchemaVersion,
      'before_label': 'before',
      'after_label': 'after',
      'changed_paths': ['agent_state.approvals'],
    });

    expect(diff.beforeLabel, 'before');
    expect(diff.afterLabel, 'after');
    expect(diff.changedPaths.single, 'agent_state.approvals');
  });

  test('artifact bundle parses transcript and provider traces', () {
    final bundle = RuntimeTestArtifactBundle.fromJson(const {
      'schema_version': runtimeTestContractSchemaVersion,
      'descriptor': {
        'kind': 'runtime_test_artifact_bundle',
        'schema_version': runtimeTestContractSchemaVersion,
      },
      'run_id': 'run-1',
      'conversation_id': 'conversation-1',
      'transcript': [
        {'role': 'user', 'content': 'hello'},
      ],
      'state_snapshot': {
        'agent_state': {},
      },
      'state_diff': {
        'schema_version': runtimeTestContractSchemaVersion,
        'changed_paths': [],
      },
      'run_logs': [
        {'kind': 'summary'},
      ],
      'tool_call_logs': [
        {'tool_name': 'vault_service.fetch_working_set'},
      ],
      'provider_traces': [
        {'provider': 'openai'},
      ],
      'deployment_events': [
        {
          'schema_version': runtimeTestContractSchemaVersion,
          'step': 'deploy',
        },
      ],
    });

    expect(bundle.runId, 'run-1');
    expect(bundle.transcript.single['role'], 'user');
    expect(bundle.providerTraces.single['provider'], 'openai');
    expect(bundle.deploymentEvents.single['step'], 'deploy');
  });
}
