import 'runtime_api_client.dart';
import 'runtime_test_models.dart';

final class RuntimeTestClient {
  RuntimeTestClient({
    RuntimeApiClient? apiClient,
    this.testToken = 'runtime-test-token',
  }) : _apiClient = apiClient ?? RuntimeApiClient();

  final RuntimeApiClient _apiClient;
  final String testToken;

  Map<String, String> get _testHeaders => <String, String>{
        'x-runtime-test-token': testToken,
      };

  Future<RuntimeTestBootstrapResult> bootstrap({
    String? vaultId,
    String runtimeMode = 'self_managed',
    String apiBaseUrl = 'https://runtime.example/',
    String authMode = 'runtime_token',
    List<String> capabilities = const <String>[
      'chat',
      'working_set',
      'llm',
      'embedding',
      'semantic_parse',
      'media_understanding',
      'multimodal_llm',
      'runtime_test_api',
    ],
  }) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/bootstrap',
      headers: _testHeaders,
      body: <String, Object?>{
        if (vaultId != null) 'vault_id': vaultId,
        'runtime_mode': runtimeMode,
        'api_base_url': apiBaseUrl,
        'auth_mode': authMode,
        'capabilities': capabilities,
      },
    );
    return RuntimeTestBootstrapResult.fromJson(response ?? const {});
  }

  Future<void> injectFixtures({
    required String vaultId,
    required List<Map<String, Object?>> records,
  }) async {
    await _apiClient.postJson(
      '/v1/runtime-test/fixtures',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        'records': records,
      },
    );
  }

  Future<void> injectWorkingSetFixtures({
    required String vaultId,
    List<Map<String, Object?>> tasks = const [],
    List<Map<String, Object?>> memories = const [],
    List<Map<String, Object?>> conversationSummaries = const [],
    List<Map<String, Object?>> reviewItems = const [],
    List<Map<String, Object?>> drafts = const [],
  }) async {
    await _apiClient.postJson(
      '/v1/runtime-test/fixtures/working-set',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        'tasks': tasks,
        'memories': memories,
        'conversation_summaries': conversationSummaries,
        'review_items': reviewItems,
        'drafts': drafts,
      },
    );
  }

  Future<void> injectAttachments({
    required String vaultId,
    required List<Map<String, Object?>> attachments,
  }) async {
    await _apiClient.postJson(
      '/v1/runtime-test/fixtures/attachments',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        'attachments': attachments,
      },
    );
  }

  Future<void> configureProviderSimulation({
    required String vaultId,
    required String provider,
    required String purpose,
    required Map<String, Object?> simulation,
  }) async {
    await _apiClient.postJson(
      '/v1/runtime-test/provider-simulation',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        'provider': provider,
        'purpose': purpose,
        'simulation': simulation,
      },
    );
  }

  Future<void> configureByokSecret({
    required String vaultId,
    required String provider,
    required String apiKey,
    required String upstreamBaseUrl,
  }) async {
    await _apiClient.postJson(
      '/v1/runtime-test/byok-secret',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        'provider': provider,
        'api_key': apiKey,
        'upstream_base_url': upstreamBaseUrl,
      },
    );
  }

  Future<int> advanceTime(int deltaMs) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/advance-time',
      headers: _testHeaders,
      body: <String, Object?>{
        'delta_ms': deltaMs,
      },
    );
    return (response?['now_ms'] as num?)?.toInt() ?? 0;
  }

  Future<int> freezeTime(int nowMs) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/time/freeze',
      headers: _testHeaders,
      body: <String, Object?>{
        'now_ms': nowMs,
      },
    );
    return (response?['now_ms'] as num?)?.toInt() ?? 0;
  }

  Future<void> forceJob({
    required String vaultId,
    required String job,
  }) async {
    await _apiClient.postJson(
      '/v1/runtime-test/force-jobs',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        'job': job,
      },
    );
  }

  Future<Map<String, dynamic>> runJob({
    required String vaultId,
    required String job,
  }) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/jobs/run',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        'job': job,
      },
    );
    return response ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> runAllJobs(String vaultId) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/jobs/run-all',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
      },
    );
    return response ?? const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> listJobs(String vaultId) async {
    final response = await _apiClient.getJson(
      '/v1/runtime-test/jobs?vault_id=$vaultId',
      headers: _testHeaders,
    );
    return _extractItems(response);
  }

  Future<List<Map<String, dynamic>>> fetchCheckpoints(String vaultId) async {
    final response = await _apiClient.getJson(
      '/v1/runtime-test/checkpoints?vault_id=$vaultId',
      headers: _testHeaders,
    );
    return _extractItems(response);
  }

  Future<Map<String, dynamic>> triggerAlarm({
    required String vaultId,
    String? approvalId,
  }) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/alarms/trigger',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        if (approvalId != null) 'approval_id': approvalId,
      },
    );
    return response ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> triggerAllDueAlarms(String vaultId) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/alarms/trigger-all-due',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
      },
    );
    return response ?? const <String, dynamic>{};
  }

  Future<void> reset({String? vaultId}) async {
    final suffix = vaultId == null ? '' : '?vault_id=$vaultId';
    await _apiClient.postJson(
      '/v1/runtime-test/reset$suffix',
      headers: _testHeaders,
    );
  }

  Future<RuntimeTestConversation> createConversation(String vaultId) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/conversations',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
      },
    );
    return RuntimeTestConversation(
      conversationId: '${response?['conversation_id'] ?? ''}',
    );
  }

  Future<RuntimeTestRunResult> sendMessage({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    final response = await _apiClient.postJson(
      '/v1/runtime-test/messages',
      headers: _testHeaders,
      body: <String, Object?>{
        'vault_id': vaultId,
        'conversation_id': conversationId,
        'message': message,
      },
    );
    return RuntimeTestRunResult.fromJson(response ?? const {});
  }

  Future<RuntimeTestRunResult> fetchRunResult(String runId) async {
    final response = await _apiClient.getJson(
      '/v1/runtime-test/runs/$runId/result',
      headers: _testHeaders,
    );
    return RuntimeTestRunResult.fromJson(response ?? const {});
  }

  Future<List<Map<String, dynamic>>> fetchTranscript(
      String conversationId) async {
    final response = await _apiClient.getJson(
      '/v1/runtime-test/conversations/$conversationId/transcript',
      headers: _testHeaders,
    );
    return _extractItems(response);
  }

  Future<List<RuntimeTestApprovalItem>> fetchApprovals(String vaultId) async {
    final response = await _apiClient.getJson(
      '/v1/runtime-test/approvals?vault_id=$vaultId',
      headers: _testHeaders,
    );
    return _extractItems(response)
        .map(RuntimeTestApprovalItem.fromJson)
        .toList(growable: false);
  }

  Future<RuntimeTestApprovalItem> fetchApproval({
    required String vaultId,
    required String approvalId,
  }) async {
    final response = await _apiClient.getJson(
      '/v1/runtime-test/approvals/$approvalId?vault_id=$vaultId',
      headers: _testHeaders,
    );
    return RuntimeTestApprovalItem.fromJson(response ?? const {});
  }

  Future<void> approve(String vaultId, String approvalId) async {
    await _apiClient.postJson(
      '/v1/runtime-test/approvals/$approvalId/approve?vault_id=$vaultId',
      headers: _testHeaders,
    );
  }

  Future<void> reject(String vaultId, String approvalId) async {
    await _apiClient.postJson(
      '/v1/runtime-test/approvals/$approvalId/reject?vault_id=$vaultId',
      headers: _testHeaders,
    );
  }

  Future<RuntimeTestSnapshot> snapshot(String vaultId, {String? label}) async {
    final labelSuffix = label == null ? '' : '&label=$label';
    final response = await _apiClient.getJson(
      '/v1/runtime-test/snapshot?vault_id=$vaultId$labelSuffix',
      headers: _testHeaders,
    );
    return RuntimeTestSnapshot.fromJson(response ?? const {});
  }

  Future<RuntimeTestStateDiff> fetchStateDiff({
    required String beforeLabel,
    required String afterLabel,
  }) async {
    final response = await _apiClient.getJson(
      '/v1/runtime-test/state-diff?before_label=$beforeLabel&after_label=$afterLabel',
      headers: _testHeaders,
    );
    return RuntimeTestStateDiff.fromJson(response ?? const {});
  }

  Future<RuntimeTestArtifactBundle> fetchArtifactBundle({
    required String runId,
    String? snapshotLabel,
  }) async {
    final suffix =
        snapshotLabel == null ? '' : '&snapshot_label=$snapshotLabel';
    final response = await _apiClient.getJson(
      '/v1/runtime-test/artifact-bundle?run_id=$runId$suffix',
      headers: _testHeaders,
    );
    return RuntimeTestArtifactBundle.fromJson(response ?? const {});
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic>? response) {
    final rawItems = response?['items'];
    if (rawItems is! List) {
      return const <Map<String, dynamic>>[];
    }
    return rawItems
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .toList(growable: false);
  }

  void dispose() {
    _apiClient.dispose();
  }
}
