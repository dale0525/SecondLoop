import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_test_models.dart';

import '../../../test_helpers/cloud_runtime_test_assertions.dart';

void main() {
  test('runtime test assertions validate response metadata and diffs', () {
    final run = RuntimeTestRunResult.fromJson(const {
      'schema_version': runtimeTestContractSchemaVersion,
      'run_id': 'run-1',
      'conversation_id': 'conversation-1',
      'status': 'waiting_approval',
      'assistant': {
        'content': 'pending approval',
      },
      'metadata': {
        'schema_version': runtimeTestContractSchemaVersion,
        'response_type': 'reminder_candidate',
        'approval_required': true,
      },
    });
    final diff = RuntimeTestStateDiff.fromJson(const {
      'schema_version': runtimeTestContractSchemaVersion,
      'before_label': 'before',
      'after_label': 'after',
      'changed_paths': ['agent_state.approvals'],
    });
    final approval = RuntimeTestApprovalItem.fromJson(const {
      'schema_version': runtimeTestContractSchemaVersion,
      'id': 'approval-1',
      'kind': 'reminder_confirmation',
    });

    expectRuntimeResponseType(run, 'reminder_candidate');
    expectApprovalRequired(run, value: true);
    expectChangedPath(diff, 'agent_state.approvals');
    expectApprovalKind(approval, 'reminder_confirmation');
  });
}
