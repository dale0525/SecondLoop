import 'package:flutter/foundation.dart';

import 'runtime_test_errors.dart';

const int runtimeTestContractSchemaVersion = 1;

const Set<String> runtimeTestResponseTypes = <String>{
  'summary',
  'plan_draft',
  'approval_request',
  'memory_candidate',
  'reminder_candidate',
  'formal_mutation_pending',
  'high_cost_confirmation',
  'external_side_effect_blocked',
  'tool_unavailable',
  'error',
};

const Set<String> runtimeTestApprovalKinds = <String>{
  'reminder_confirmation',
  'memory_confirmation',
  'task_mutation_confirmation',
};

@immutable
class RuntimeTestFixtureRecord {
  const RuntimeTestFixtureRecord({
    required this.kind,
    required this.id,
    required this.fields,
  });

  final String kind;
  final String id;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind,
      'id': id,
      ...fields,
    };
  }
}

@immutable
class RuntimeProviderSimulationConfig {
  const RuntimeProviderSimulationConfig({
    required this.mode,
    this.output,
  });

  final String mode;
  final Map<String, Object?>? output;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode,
      if (output != null) 'output': output,
    };
  }
}

@immutable
class RuntimeTestSnapshot {
  const RuntimeTestSnapshot({
    required this.agentState,
    required this.providerSimulation,
  });

  final Map<String, dynamic> agentState;
  final Map<String, dynamic> providerSimulation;

  factory RuntimeTestSnapshot.fromJson(Map<String, dynamic> json) {
    return RuntimeTestSnapshot(
      agentState:
          Map<String, dynamic>.from(json['agent_state'] as Map? ?? const {}),
      providerSimulation: Map<String, dynamic>.from(
        json['provider_simulation'] as Map? ?? const {},
      ),
    );
  }
}

@immutable
class RuntimeTestBootstrapResult {
  const RuntimeTestBootstrapResult({
    required this.vaultId,
    required this.runtimeToken,
    required this.conversationSeed,
    required this.manifest,
  });

  final String vaultId;
  final String runtimeToken;
  final String conversationSeed;
  final Map<String, dynamic> manifest;

  factory RuntimeTestBootstrapResult.fromJson(Map<String, dynamic> json) {
    return RuntimeTestBootstrapResult(
      vaultId: '${json['vault_id'] ?? ''}',
      runtimeToken: '${json['runtime_token'] ?? ''}',
      conversationSeed: '${json['conversation_seed'] ?? ''}',
      manifest: Map<String, dynamic>.from(
        json['manifest'] as Map? ?? const {},
      ),
    );
  }
}

@immutable
class RuntimeTestConversation {
  const RuntimeTestConversation({
    required this.conversationId,
  });

  final String conversationId;
}

@immutable
class RuntimeTestRunResult {
  const RuntimeTestRunResult({
    required this.schemaVersion,
    required this.runId,
    required this.conversationId,
    required this.status,
    required this.assistantContent,
    required this.metadata,
  });

  final int schemaVersion;
  final String runId;
  final String conversationId;
  final String status;
  final String assistantContent;
  final Map<String, dynamic> metadata;

  factory RuntimeTestRunResult.fromJson(Map<String, dynamic> json) {
    _requireSchemaVersion(json, context: 'run result');
    _requireSchemaVersion(
      Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
      context: 'response metadata',
    );
    return RuntimeTestRunResult(
      schemaVersion: runtimeTestContractSchemaVersion,
      runId: '${json['run_id'] ?? ''}',
      conversationId: '${json['conversation_id'] ?? ''}',
      status: '${json['status'] ?? ''}',
      assistantContent: '${(json['assistant'] as Map?)?['content'] ?? ''}',
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const {},
      ),
    );
  }
}

@immutable
class RuntimeTestApprovalItem {
  const RuntimeTestApprovalItem({
    required this.schemaVersion,
    required this.id,
    required this.kind,
    required this.payload,
  });

  final int schemaVersion;
  final String id;
  final String kind;
  final Map<String, dynamic> payload;

  factory RuntimeTestApprovalItem.fromJson(Map<String, dynamic> json) {
    _requireSchemaVersion(json, context: 'approval item');
    return RuntimeTestApprovalItem(
      schemaVersion: runtimeTestContractSchemaVersion,
      id: '${json['id'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      payload: Map<String, dynamic>.from(json),
    );
  }
}

@immutable
class RuntimeTestStateDiff {
  const RuntimeTestStateDiff({
    required this.schemaVersion,
    required this.beforeLabel,
    required this.afterLabel,
    required this.changedPaths,
  });

  final int schemaVersion;
  final String beforeLabel;
  final String afterLabel;
  final List<String> changedPaths;

  factory RuntimeTestStateDiff.fromJson(Map<String, dynamic> json) {
    _requireSchemaVersion(json, context: 'state diff');
    return RuntimeTestStateDiff(
      schemaVersion: runtimeTestContractSchemaVersion,
      beforeLabel: '${json['before_label'] ?? ''}',
      afterLabel: '${json['after_label'] ?? ''}',
      changedPaths: (json['changed_paths'] as List? ?? const [])
          .map((item) => '$item')
          .toList(growable: false),
    );
  }
}

@immutable
class RuntimeTestArtifactBundle {
  const RuntimeTestArtifactBundle({
    required this.schemaVersion,
    required this.descriptor,
    required this.runId,
    required this.conversationId,
    required this.transcript,
    required this.stateSnapshot,
    required this.stateDiff,
    required this.runLogs,
    required this.toolCallLogs,
    required this.providerTraces,
    required this.deploymentEvents,
  });

  final int schemaVersion;
  final RuntimeTestArtifactDescriptor descriptor;
  final String runId;
  final String conversationId;
  final List<Map<String, dynamic>> transcript;
  final Map<String, dynamic> stateSnapshot;
  final Map<String, dynamic> stateDiff;
  final List<Map<String, dynamic>> runLogs;
  final List<Map<String, dynamic>> toolCallLogs;
  final List<Map<String, dynamic>> providerTraces;
  final List<Map<String, dynamic>> deploymentEvents;

  factory RuntimeTestArtifactBundle.fromJson(Map<String, dynamic> json) {
    _requireSchemaVersion(json, context: 'artifact bundle');
    return RuntimeTestArtifactBundle(
      schemaVersion: runtimeTestContractSchemaVersion,
      descriptor: RuntimeTestArtifactDescriptor.fromJson(
        Map<String, dynamic>.from(json['descriptor'] as Map? ?? const {}),
      ),
      runId: '${json['run_id'] ?? ''}',
      conversationId: '${json['conversation_id'] ?? ''}',
      transcript: _mapList(json['transcript']),
      stateSnapshot: Map<String, dynamic>.from(
        json['state_snapshot'] as Map? ?? const {},
      ),
      stateDiff: Map<String, dynamic>.from(
        json['state_diff'] as Map? ?? const {},
      ),
      runLogs: _mapList(json['run_logs']),
      toolCallLogs: _mapList(json['tool_call_logs']),
      providerTraces: _mapList(json['provider_traces']),
      deploymentEvents: _mapList(json['deployment_events']),
    );
  }
}

@immutable
class RuntimeTestArtifactDescriptor {
  const RuntimeTestArtifactDescriptor({
    required this.kind,
    required this.schemaVersion,
  });

  final String kind;
  final int schemaVersion;

  factory RuntimeTestArtifactDescriptor.fromJson(Map<String, dynamic> json) {
    _requireSchemaVersion(json, context: 'artifact descriptor');
    return RuntimeTestArtifactDescriptor(
      kind: '${json['kind'] ?? ''}',
      schemaVersion: runtimeTestContractSchemaVersion,
    );
  }
}

List<Map<String, dynamic>> _mapList(Object? rawItems) {
  if (rawItems is! List) {
    return const <Map<String, dynamic>>[];
  }
  return rawItems
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry('$key', value)))
      .toList(growable: false);
}

void _requireSchemaVersion(
  Map<String, dynamic> json, {
  required String context,
}) {
  final rawVersion = json['schema_version'];
  if (rawVersion is! num) {
    throw RuntimeTestContractException(
      'Missing schema version for $context runtime test contract.',
    );
  }
  if (rawVersion.toInt() != runtimeTestContractSchemaVersion) {
    throw RuntimeTestContractException(
      'Unsupported schema version ${rawVersion.toInt()} for $context runtime test contract.',
    );
  }
}
