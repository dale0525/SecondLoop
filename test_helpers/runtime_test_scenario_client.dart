import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/cloud/runtime_api_client.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/runtime_test_client.dart';
import 'package:secondloop/core/cloud/runtime_test_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef RuntimeScenarioResponder = Future<http.Response> Function(
  http.Request request,
);

Future<RuntimeTestClient> createRuntimeTestScenarioClient(
  RuntimeScenarioResponder responder,
) async {
  // This helper is only used from tests, but it lives under test_helpers/.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final store = RuntimeConnectionStore();
  await store.saveConnection(
    const CloudRuntimeConnection(
      profile: CloudRuntimeProfile(
        runtimeMode: CloudRuntimeMode.selfManaged,
        apiBaseUrl: 'https://runtime.example/',
        authMode: CloudRuntimeAuthMode.runtimeToken,
        authToken: 'runtime-token-1',
        capabilityManifestId: 'manifest-self-1',
        manifestVersion: 1,
      ),
      manifest: CloudRuntimeManifest(
        manifestVersion: 1,
        runtimeMode: CloudRuntimeMode.selfManaged,
        apiBaseUrl: 'https://runtime.example/',
        authMode: CloudRuntimeAuthMode.runtimeToken,
        capabilities: [
          CloudRuntimeCapability('chat'),
          CloudRuntimeCapability('working_set'),
          CloudRuntimeCapability('runtime_test_api'),
        ],
      ),
    ),
  );
  return RuntimeTestClient(
    apiClient: RuntimeApiClient(
      connectionStore: RuntimeConnectionStore(),
      httpClient: MockClient(responder),
    ),
  );
}

http.Response jsonScenarioResponse(Object body, [int statusCode = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: const {
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

Map<String, Object?> buildScenarioRunResult({
  required String responseType,
  required String content,
  String status = 'completed',
  bool approvalRequired = false,
  bool requiresHighCostConfirmation = false,
  Map<String, Object?> referencedEntities = const <String, Object?>{},
  List<Map<String, Object?>> proposedMutations = const <Map<String, Object?>>[],
  List<Map<String, Object?>> draftEntities = const <Map<String, Object?>>[],
}) {
  return <String, Object?>{
    'schema_version': runtimeTestContractSchemaVersion,
    'run_id': 'run-1',
    'conversation_id': 'conversation-1',
    'status': status,
    'assistant': <String, Object?>{'content': content},
    'metadata': <String, Object?>{
      'schema_version': runtimeTestContractSchemaVersion,
      'response_type': responseType,
      'approval_required': approvalRequired,
      'requires_high_cost_confirmation': requiresHighCostConfirmation,
      'referenced_entities': referencedEntities,
      'proposed_mutations': proposedMutations,
      'draft_entities': draftEntities,
    },
  };
}

Map<String, Object?> buildScenarioApprovalItem({
  required String id,
  required String kind,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return <String, Object?>{
    'schema_version': runtimeTestContractSchemaVersion,
    'id': id,
    'kind': kind,
    ...extra,
  };
}

Map<String, Object?> buildScenarioStateDiff({
  required List<String> changedPaths,
  String beforeLabel = 'before',
  String afterLabel = 'after',
}) {
  return <String, Object?>{
    'schema_version': runtimeTestContractSchemaVersion,
    'before_label': beforeLabel,
    'after_label': afterLabel,
    'changed_paths': changedPaths,
  };
}

Map<String, Object?> buildScenarioArtifactBundle({
  List<Map<String, Object?>> transcript = const <Map<String, Object?>>[],
  List<String> changedPaths = const <String>[],
  List<Map<String, Object?>> runLogs = const <Map<String, Object?>>[],
  List<Map<String, Object?>> toolCallLogs = const <Map<String, Object?>>[],
  List<Map<String, Object?>> providerTraces = const <Map<String, Object?>>[],
  List<Map<String, Object?>> deploymentEvents = const <Map<String, Object?>>[],
}) {
  return <String, Object?>{
    'schema_version': runtimeTestContractSchemaVersion,
    'descriptor': <String, Object?>{
      'kind': 'runtime_test_artifact_bundle',
      'schema_version': runtimeTestContractSchemaVersion,
    },
    'run_id': 'run-1',
    'conversation_id': 'conversation-1',
    'transcript': transcript,
    'state_snapshot': const <String, Object?>{
      'agent_state': <String, Object?>{},
    },
    'state_diff': buildScenarioStateDiff(changedPaths: changedPaths),
    'run_logs': runLogs,
    'tool_call_logs': toolCallLogs,
    'provider_traces': providerTraces,
    'deployment_events': deploymentEvents
        .map(
          (event) => <String, Object?>{
            'schema_version': runtimeTestContractSchemaVersion,
            ...event,
          },
        )
        .toList(growable: false),
  };
}
