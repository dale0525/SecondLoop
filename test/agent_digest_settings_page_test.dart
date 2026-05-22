import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/cloud/agent_digest_client.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/settings/agent_digest_settings_page.dart';
import 'package:secondloop/features/settings/settings_ui.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

import 'test_i18n.dart';

void main() {
  test('AgentDigestClient uses managed-vault digest endpoints', () async {
    final requests = <http.Request>[];
    final client = AgentDigestClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'exists': true,
              'version': 'digest-v1',
              'byte_len': 512,
              'generated_at_ms': 1700000000000,
              'device_id': 'device-1',
              'updated_at_ms': 1700000001000,
            }),
            200,
          );
        }
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['version'], 'digest-v2');
          expect(body['memories'], isA<List<Object?>>());
          return http.Response(
            jsonEncode({
              'exists': true,
              'version': 'digest-v2',
              'byte_len': 256,
              'generated_at_ms': 1700000002000,
              'device_id': 'device-1',
              'updated_at_ms': 1700000003000,
            }),
            200,
          );
        }
        if (request.method == 'DELETE') {
          return http.Response(jsonEncode({'ok': true, 'deleted': true}), 200);
        }
        fail('unexpected method ${request.method}');
      }),
    );

    final meta = await client.fetchMeta(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );
    final uploaded = await client.uploadDigest(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
      digest: {
        'version': 'digest-v2',
        'generated_at_ms': 1700000002000,
        'device_id': 'device-1',
        'memories': const [],
      },
    );
    final deleted = await client.deleteDigest(
      managedVaultBaseUrl: 'https://vault.test',
      vaultId: 'vault-1',
      idToken: 'token-1',
    );

    expect(meta.version, 'digest-v1');
    expect(uploaded.version, 'digest-v2');
    expect(deleted, isTrue);
    expect(requests.map((request) => request.method), ['GET', 'PUT', 'DELETE']);
    expect(
      requests.map((request) => request.url.path),
      [
        '/api/v1/vaults/vault-1/agent-digest/meta',
        '/api/v1/vaults/vault-1/agent-digest',
        '/api/v1/vaults/vault-1/agent-digest',
      ],
    );
    expect(
      requests.every(
        (request) => request.headers['authorization'] == 'Bearer token-1',
      ),
      isTrue,
    );
  });

  test('SecretaryController builds bounded digest without full vault text',
      () async {
    final nowMs = DateTime(2026, 4, 29, 9).millisecondsSinceEpoch;
    final backend = _DigestBackend(
      memoryPages: [
        _memoryPage(
          id: 'mem-1',
          pageType: 'preference',
          title: 'Morning meetings',
          body: 'Prefers morning meetings.',
        ),
        _memoryPage(
          id: 'mem-archived',
          state: 'archived',
          title: 'Archived',
          body: 'Should not appear.',
        ),
      ],
      proposals: [
        _proposal(
          id: 'proposal-1',
          title: 'Pending preference',
          body: 'Likes written agendas.',
        ),
      ],
    );
    final controller = SecretaryController(
      backend: backend,
      planningEngine: RuleBasedPlanningEngine(
        nowLocal: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
      ),
    );

    final digest = await controller.buildAgentDigest(
      Uint8List.fromList(List<int>.filled(32, 1)),
      todos: [
        _todo(
          id: 'due-1',
          title: 'Submit review',
          dueAtMs: nowMs + const Duration(days: 1).inMilliseconds,
          updatedAtMs: nowMs,
        ),
        _todo(
          id: 'stale-1',
          title: 'Clarify launch plan',
          updatedAtMs: nowMs - const Duration(days: 9).inMilliseconds,
        ),
        _todo(
          id: 'done-1',
          title: 'Already done',
          status: 'done',
          updatedAtMs: nowMs,
        ),
      ],
      deviceId: 'device-1',
      localeTag: 'en-US',
      nowMs: nowMs,
    );

    final json = digest.toJson();
    expect(json['version'], 'agent-digest-$nowMs');
    expect(json['device_id'], 'device-1');
    expect(json['locale'], 'en-US');
    expect(json['memories'], hasLength(1));
    expect(json['preferences'], hasLength(1));
    expect(json['upcoming_deadlines'], hasLength(1));
    expect(json['stale_tasks'], hasLength(1));
    expect(
        json['commitments'],
        isNot(contains(predicate<Map<String, Object?>>(
          (item) => item['todo_id'] == 'done-1',
        ))));
    expect(json['recent_unresolved_captures'], hasLength(1));
    expect(jsonEncode(json), isNot(contains('Should not appear')));
  });

  testWidgets('AgentDigestSettingsPage requires confirmation before upload',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final nowMs = DateTime(2026, 4, 29, 9).millisecondsSinceEpoch;
    final api = _FakeAgentDigestApi(
      meta: const AgentDigestMeta.empty(),
    );
    final syncStore = SyncConfigStore(
      scopeKey: 'agent-digest-settings-test',
      managedVaultDefaultBaseUrl: 'https://vault.test',
    );
    await syncStore.writeManagedVaultSyncSettings(
      baseUrl: 'https://vault.test',
      remoteRoot: 'vault-1',
      autoEnabled: true,
    );

    final controller = SecretaryController(
      backend: _DigestBackend(
        memoryPages: [
          _memoryPage(
            id: 'mem-1',
            title: 'Morning meetings',
            body: 'Prefers morning meetings.',
          ),
        ],
      ),
      planningEngine: RuleBasedPlanningEngine(
        nowLocal: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: MaterialApp(
            home: CloudAuthScope(
              controller: const _FakeCloudAuthController(),
              child: SubscriptionScope(
                controller: _FakeSubscriptionController(
                  SubscriptionStatus.entitled,
                ),
                child: Scaffold(
                  body: AgentDigestSettingsPage(
                    api: api,
                    configStore: syncStore,
                    secretaryController: controller,
                    todosLoader: (_) async => [
                      _todo(
                        id: 'todo-1',
                        title: 'Submit review',
                        dueAtMs: nowMs + const Duration(days: 1).inMilliseconds,
                        updatedAtMs: nowMs,
                      ),
                    ],
                    deviceIdLoader: () async => 'device-1',
                    nowMsProvider: () => nowMs,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPageShell), findsOneWidget);
    expect(find.byType(SettingsSection), findsWidgets);
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent_digest_regenerate')));
    await tester.pumpAndSettle();
    expect(api.uploadedDigests, isEmpty);
    expect(find.text('Regenerate Cloud Agent Digest?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent_digest_confirm_upload')));
    await tester.pumpAndSettle();

    expect(api.uploadedDigests, hasLength(1));
    expect(api.uploadedDigests.single['version'], 'agent-digest-$nowMs');
    expect(find.text('Enabled'), findsOneWidget);
  });
}

final class _DigestBackend implements SecretaryBackend {
  _DigestBackend({
    this.memoryPages = const <MemoryPageRecord>[],
    this.proposals = const <SecretaryMemoryProposalRecord>[],
  });

  final List<MemoryPageRecord> memoryPages;
  final List<SecretaryMemoryProposalRecord> proposals;

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    if (state == null) return memoryPages;
    return memoryPages.where((page) => page.state == state).toList();
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    if (state == null) return proposals;
    return proposals.where((proposal) => proposal.state == state).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeAgentDigestApi implements AgentDigestApi {
  _FakeAgentDigestApi({required AgentDigestMeta meta}) : _meta = meta;

  AgentDigestMeta _meta;
  final List<Map<String, Object?>> uploadedDigests = <Map<String, Object?>>[];

  @override
  Future<AgentDigestMeta> fetchMeta({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    return _meta;
  }

  @override
  Future<AgentDigestMeta> uploadDigest({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required Map<String, Object?> digest,
  }) async {
    uploadedDigests.add(digest);
    _meta = AgentDigestMeta(
      exists: true,
      version: digest['version']! as String,
      byteLen: 512,
      generatedAtMs: digest['generated_at_ms']! as int,
      deviceId: digest['device_id']! as String,
      updatedAtMs: digest['generated_at_ms']! as int,
    );
    return _meta;
  }

  @override
  Future<bool> deleteDigest({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    _meta = const AgentDigestMeta.empty();
    return true;
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  const _FakeCloudAuthController();

  @override
  String? get uid => 'vault-1';

  @override
  String? get email => 'user@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token-1';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

MemoryPageRecord _memoryPage({
  required String id,
  String pageType = 'fact',
  String state = 'active',
  required String title,
  required String body,
}) {
  return MemoryPageRecord(
    pageId: id,
    pageType: pageType,
    state: state,
    sourceCount: platformIntFromInt(1),
    title: title,
    summary: body,
    body: body,
    primaryEvidenceJson: '{}',
    sourceDocumentIdsJson: '[]',
    confidenceLevel: 0.9,
    humanCorrected: false,
    createdAtMs: platformIntFromInt(1700000000000),
    updatedAtMs: platformIntFromInt(1700000000000),
  );
}

SecretaryMemoryProposalRecord _proposal({
  required String id,
  required String title,
  required String body,
}) {
  return SecretaryMemoryProposalRecord(
    id: id,
    sourceMessageId: 'message-$id',
    kind: 'preference',
    title: title,
    body: body,
    confidence: 0.8,
    state: 'pending',
    actionHint: 'propose',
    createdAtMs: platformIntFromInt(1700000000000),
    updatedAtMs: platformIntFromInt(1700000000000),
  );
}

Todo _todo({
  required String id,
  required String title,
  String status = 'open',
  int? dueAtMs,
  required int updatedAtMs,
}) {
  return Todo(
    id: id,
    title: title,
    dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
    status: status,
    createdAtMs: platformIntFromInt(updatedAtMs),
    updatedAtMs: platformIntFromInt(updatedAtMs),
  );
}
