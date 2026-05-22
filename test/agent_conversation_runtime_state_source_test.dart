import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'managed pro conversation reads right rail tasks and memories from runtime state',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [
            {
              'turn_id': 'turn-1',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'assistant',
              'content': 'Runtime state loaded.',
              'created_at_ms': 1700000000000,
            }
          ],
          'working_set_records': [],
          'tasks': [
            {
              'id': 'task-weekly',
              'kind': 'task',
              'title': '完成周报',
              'status': 'open',
            }
          ],
          'memory_records': [
            {
              'id': 'memory-language',
              'kind': 'memory',
              'text': '任务回复请使用中文',
            }
          ],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': null,
          'audit_refs': [],
        }),
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: _ThrowingLocalStoreBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.text('Runtime state loaded.'), findsOneWidget);
      expect(find.textContaining('完成周报'), findsWidgets);
      expect(find.textContaining('任务回复请使用中文'), findsWidgets);
    },
  );

  testWidgets(
    'managed pro conversation right rail merges runtime memory when context snapshot is stale',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [
            {
              'turn_id': 'turn-1',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'assistant',
              'content': 'Runtime state loaded.',
              'created_at_ms': 1700000000000,
            }
          ],
          'working_set_records': [],
          'tasks': [],
          'memory_records': [
            {
              'id': 'memory-birthday',
              'kind': 'memory',
              'text': '孩子生日是 2018 年 6 月 1 日',
              'state': 'active',
            }
          ],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': {
            'id': 'context-snapshot-stale',
            'generated_at_ms': 1700000000000,
            'packet': {
              'conversation_id': 'loop_home',
              'working_set': {'records': []},
              'memory_records': [],
            },
          },
          'audit_refs': [],
        }),
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: _ThrowingLocalStoreBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.textContaining('孩子生日是 2018 年 6 月 1 日'), findsWidgets);
    },
  );

  testWidgets(
    'managed pro conversation right rail prefers current runtime task title over stale context snapshot',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [
            {
              'turn_id': 'turn-1',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'assistant',
              'content': 'Runtime state loaded.',
              'created_at_ms': 1700000000000,
            }
          ],
          'working_set_records': [],
          'tasks': [
            {
              'id': 'task-expense',
              'kind': 'task',
              'title': '提交报销',
              'status': 'open',
            }
          ],
          'memory_records': [],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': {
            'id': 'context-snapshot-stale-task',
            'generated_at_ms': 1700000000000,
            'packet': {
              'conversation_id': 'loop_home',
              'working_set': {
                'records': [
                  {
                    'id': 'task-expense',
                    'kind': 'task',
                    'title': '整理报销材料',
                    'status': 'open',
                  }
                ],
              },
            },
          },
          'audit_refs': [],
        }),
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: _ThrowingLocalStoreBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.textContaining('提交报销'), findsWidgets);
      expect(find.textContaining('整理报销材料'), findsNothing);
    },
  );

  testWidgets(
    'managed pro conversation right rail shows runtime media attachments',
    (tester) async {
      const attachmentId = 'sha-image-1';
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [
            {
              'turn_id': 'turn-user-media',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'user',
              'content': '提取这张图里的文字。',
              'attachment_refs': [attachmentId],
              'attachments': [
                {
                  'attachment_id': attachmentId,
                  'blob_id': attachmentId,
                  'sha256': attachmentId,
                  'filename': 'qa-ocr-sample.png',
                  'mime_type': 'image/png',
                  'media_type': 'image',
                },
              ],
              'created_at_ms': 1700000000000,
            },
            {
              'turn_id': 'turn-assistant-media',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'assistant',
              'content': '已提取图片文字。',
              'created_at_ms': 1700000000100,
            },
          ],
          'working_set_records': [
            {
              'id': 'media-result-sha-image-1',
              'kind': 'media_result',
              'attachment_id': attachmentId,
              'media_type': 'image',
              'ocr_text': 'QA MEDIA',
              'summary': '图片中包含 QA MEDIA。',
              'status': 'completed',
            },
          ],
          'tasks': [],
          'memory_records': [],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': null,
          'audit_refs': [],
        }),
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: _ThrowingLocalStoreBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.text('qa-ocr-sample.png'), findsWidgets);
      expect(find.textContaining('QA MEDIA'), findsWidgets);
    },
  );

  testWidgets(
    'managed pro conversation shows audio meeting media result under assistant reply',
    (tester) async {
      const attachmentId = 'sha-audio-1';
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [
            {
              'turn_id': 'turn-user-audio',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'user',
              'content': '生成会议纪要、决策和行动项。',
              'attachment_refs': [attachmentId],
              'attachments': [
                {
                  'attachment_id': attachmentId,
                  'blob_id': attachmentId,
                  'sha256': attachmentId,
                  'filename': 'qa-meeting-audio.m4a',
                  'mime_type': 'audio/mp4',
                  'media_type': 'audio',
                },
              ],
              'created_at_ms': 1700000000000,
            },
            {
              'turn_id': 'turn-assistant-audio',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'assistant',
              'content': '已为您生成会议纪要、决策和行动项：',
              'created_at_ms': 1700000000100,
            },
          ],
          'working_set_records': [
            {
              'id': 'media-result-sha-audio-1',
              'kind': 'media_result',
              'attachment_id': attachmentId,
              'media_type': 'audio',
              'transcript': 'Alex: 我们下周三前确认发布清单。',
              'meeting_minutes': '会议纪要：团队确认发布清单和预算节奏。',
              'decisions': ['同意 6 月 1 日发布。'],
              'action_items': ['Alex 跟进预算确认。'],
              'status': 'completed',
            },
          ],
          'tasks': [],
          'memory_records': [],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': null,
          'audit_refs': [],
        }),
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: _ThrowingLocalStoreBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inlineResult = find.byKey(
        const ValueKey('agent_assistant_media_results_turn-assistant-audio'),
      );

      expect(inlineResult, findsOneWidget);
      expect(
        find.descendant(
          of: inlineResult,
          matching: find.textContaining('Alex: 我们下周三前确认发布清单。'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inlineResult,
          matching: find.textContaining('会议纪要：团队确认发布清单和预算节奏。'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inlineResult,
          matching: find.textContaining('同意 6 月 1 日发布。'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inlineResult,
          matching: find.textContaining('Alex 跟进预算确认。'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'managed pro conversation hydrates audio attachment bytes for preview',
    (tester) async {
      const attachmentId = 'sha-audio-preview-1';
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [
            {
              'turn_id': 'turn-user-audio-preview',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'user',
              'content': '生成会议纪要、决策和行动项。',
              'attachment_refs': [attachmentId],
              'attachments': [
                {
                  'attachment_id': attachmentId,
                  'filename': 'qa-meeting-audio.m4a',
                  'mime_type': 'audio/mp4',
                  'media_type': 'audio',
                },
              ],
              'created_at_ms': 1700000000000,
            },
          ],
          'working_set_records': [],
          'tasks': [],
          'memory_records': [],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': null,
          'audit_refs': [],
        }),
      );
      final fetcher = _RuntimeAttachmentBytesFetcher(
        bytesByAttachmentId: const {
          attachmentId: <int>[0, 1, 2, 3],
        },
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: _ThrowingLocalStoreBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeConversationSender: fetcher,
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetcher.fetches, [('uid_1', attachmentId)]);
    },
  );

  testWidgets(
    'managed pro conversation loads runtime state after cloud auth warms',
    (tester) async {
      final controller = _MutableCloudAuthController();
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [
            {
              'turn_id': 'turn-restored',
              'conversation_id': 'loop_home',
              'vault_id': 'uid_1',
              'role': 'assistant',
              'content': '重启后从 runtime 恢复的聊天记录。',
              'created_at_ms': 1700000000000,
            }
          ],
          'working_set_records': [],
          'tasks': [],
          'memory_records': [],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': null,
          'audit_refs': [],
        }),
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: CloudAuthScope(
                controller: controller,
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, isEmpty);
      expect(find.text('重启后从 runtime 恢复的聊天记录。'), findsNothing);

      controller.setUid('uid_1');
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.text('重启后从 runtime 恢复的聊天记录。'), findsOneWidget);
    },
  );
}

final class _RuntimeAttachmentBytesFetcher
    implements
        ChatRuntimeConversationSender,
        ChatRuntimeAttachmentContentFetcher {
  _RuntimeAttachmentBytesFetcher({required this.bytesByAttachmentId});

  final Map<String, List<int>> bytesByAttachmentId;
  final List<(String, String)> fetches = <(String, String)>[];

  @override
  Future<Uint8List?> fetchAttachmentBytes({
    required String vaultId,
    required String attachmentId,
  }) async {
    fetches.add((vaultId, attachmentId));
    final bytes = bytesByAttachmentId[attachmentId];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    throw StateError('send should not be used');
  }
}

final class _FakeRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _FakeRuntimeAgentStateRepository(this.state);

  final RuntimeAgentState state;
  final List<(String, String)> requests = <(String, String)>[];

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    requests.add((vaultId, conversationId));
    return state;
  }
}

final class _ThrowingLocalStoreBackend extends TestAppBackend
    implements SecretaryBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    throw StateError('listTodos should not be used');
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    throw StateError('listMemoryPages should not be used');
  }

  @override
  Future<SecretaryMemoryProposalRecord> createSecretaryMemoryProposal(
    Uint8List key, {
    String? sourceMessageId,
    required String kind,
    required String title,
    required String body,
    required double confidence,
    String? sourceRefsJson,
    String? actionHint,
    required int nowMs,
  }) async {
    throw StateError('createSecretaryMemoryProposal should not be used');
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    throw StateError('acceptSecretaryMemoryProposal should not be used');
  }

  @override
  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> getMemoryPage(
    Uint8List key, {
    required String pageId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> correctMemoryPage(
    Uint8List key, {
    required String pageId,
    required String title,
    required String summary,
    required String body,
    String? reason,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }
}

final class _CloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'qa@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'id-token';

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

final class _MutableCloudAuthController extends ChangeNotifier
    implements CloudAuthController {
  String? _uid;

  void setUid(String? value) {
    _uid = value;
    notifyListeners();
  }

  @override
  String? get uid => _uid;

  @override
  String? get email => 'qa@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'id-token';

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
  Future<void> signOut() async => setUid(null);

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
