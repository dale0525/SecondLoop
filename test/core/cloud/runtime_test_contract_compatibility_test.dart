import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_test_errors.dart';
import 'package:secondloop/core/cloud/runtime_test_models.dart';

void main() {
  test('runtime test models accept the current contract schema version', () {
    final run = RuntimeTestRunResult.fromJson(const {
      'schema_version': runtimeTestContractSchemaVersion,
      'run_id': 'run-1',
      'conversation_id': 'conversation-1',
      'status': 'completed',
      'assistant': {'content': 'summary output'},
      'metadata': {
        'schema_version': runtimeTestContractSchemaVersion,
        'response_type': 'summary',
        'approval_required': false,
      },
    });
    final approval = RuntimeTestApprovalItem.fromJson(const {
      'schema_version': runtimeTestContractSchemaVersion,
      'id': 'approval-1',
      'kind': 'reminder_confirmation',
    });
    final diff = RuntimeTestStateDiff.fromJson(const {
      'schema_version': runtimeTestContractSchemaVersion,
      'before_label': 'before',
      'after_label': 'after',
      'changed_paths': ['agent_state.approvals'],
    });
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
      'state_snapshot': {},
      'state_diff': {
        'schema_version': runtimeTestContractSchemaVersion,
        'changed_paths': <String>[],
      },
      'run_logs': [],
      'tool_call_logs': [],
      'provider_traces': [],
      'deployment_events': [
        {
          'schema_version': runtimeTestContractSchemaVersion,
          'step': 'deploy',
          'status': 'ok',
        },
      ],
    });

    expect(run.metadata['response_type'], 'summary');
    expect(approval.kind, 'reminder_confirmation');
    expect(diff.changedPaths.single, 'agent_state.approvals');
    expect(bundle.descriptor.kind, 'runtime_test_artifact_bundle');
    expect(bundle.deploymentEvents.single['step'], 'deploy');
  });

  test('runtime test models reject incompatible contract schema versions', () {
    expect(
      () => RuntimeTestRunResult.fromJson(const {
        'schema_version': runtimeTestContractSchemaVersion + 1,
        'run_id': 'run-1',
        'conversation_id': 'conversation-1',
        'status': 'completed',
        'assistant': {'content': 'summary output'},
        'metadata': {
          'schema_version': runtimeTestContractSchemaVersion + 1,
          'response_type': 'summary',
          'approval_required': false,
        },
      }),
      throwsA(isA<RuntimeTestContractException>()),
    );
    expect(
      () => RuntimeTestApprovalItem.fromJson(const {
        'schema_version': runtimeTestContractSchemaVersion + 1,
        'id': 'approval-1',
        'kind': 'reminder_confirmation',
      }),
      throwsA(isA<RuntimeTestContractException>()),
    );
    expect(
      () => RuntimeTestStateDiff.fromJson(const {
        'schema_version': runtimeTestContractSchemaVersion + 1,
        'before_label': 'before',
        'after_label': 'after',
        'changed_paths': <String>[],
      }),
      throwsA(isA<RuntimeTestContractException>()),
    );
    expect(
      () => RuntimeTestArtifactBundle.fromJson(const {
        'schema_version': runtimeTestContractSchemaVersion + 1,
        'descriptor': {
          'kind': 'runtime_test_artifact_bundle',
          'schema_version': runtimeTestContractSchemaVersion + 1,
        },
        'run_id': 'run-1',
        'conversation_id': 'conversation-1',
      }),
      throwsA(isA<RuntimeTestContractException>()),
    );
  });

  test(
      'runtime test response types and approval kinds stay aligned with server expectations',
      () {
    expect(
      runtimeTestResponseTypes,
      equals(<String>{
        'assistant_message',
        'summary',
        'clarification_request',
        'task_created',
        'plan_draft',
        'memory_candidate',
        'reminder_candidate',
        'recurring_reminder_candidate',
        'calendar_event_candidate',
        'email_draft',
        'formal_mutation_pending',
        'high_cost_confirmation',
        'external_side_effect_blocked',
        'needs_configuration',
        'tool_unavailable',
        'error',
      }),
    );
    expect(
      runtimeTestApprovalKinds,
      equals(<String>{
        'task_mutation_confirmation',
        'memory_confirmation',
        'reminder_confirmation',
        'recurring_reminder_confirmation',
        'calendar_event_confirmation',
        'email_send_confirmation',
        'high_cost_confirmation',
        'external_side_effect_confirmation',
      }),
    );
  });
}
