import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'second canonical Stitch screen renders runtime web research continuity',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(_secondScreenState());

      await tester.binding.setSurfaceSize(const Size(780, 2770));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AppShell(
                    chatTabBuilder: (_, __) => AgentConversationPage(
                      conversation: const Conversation(
                        id: 'loop_home',
                        title: 'Loop',
                        createdAtMs: 0,
                        updatedAtMs: 0,
                      ),
                      isTabActive: true,
                      runtimeAgentStateRepository: repository,
                    ),
                    reviewTabBuilder: (_, __) => const SizedBox(),
                    notesTabBuilder: (_, __) => const SizedBox(),
                    memoryTabBuilder: (_, __) => const SizedBox(),
                    settingsTabBuilder: (_, __) => const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SecondLoop'), findsOneWidget);
      expect(find.text('Managed Pro'), findsOneWidget);
      expect(find.text('web-research'), findsOneWidget);
      expect(find.text('SEARCH RESULT'), findsOneWidget);
      expect(find.text('web_research'), findsOneWidget);
      expect(find.text('VERIFIED SOURCES'), findsOneWidget);
      expect(
        find.text('iPhone 16 and iPhone 16 Plus - Apple'),
        findsOneWidget,
      );
      expect(find.text('Apple Event: Everything Announced'), findsOneWidget);
      expect(find.text('citations required'), findsOneWidget);
      expect(find.text('skill_result_response'), findsOneWidget);
      expect(find.text('Entity Ref:'), findsNothing);
      expect(
        find.text('Context used: previous turn + recent_turns + web research'),
        findsOneWidget,
      );
      expect(find.text('Extracted Evidence'), findsOneWidget);
      expect(find.textContaining('Trace ID: SRCH-2026-05-12'), findsOneWidget);
      expect(find.text('Model Gateway: Post-processed'), findsOneWidget);
      expect(find.text('Ask a follow-up...'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('agent_operating_extracted_evidence_toggle')),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('MATCH: term[iPhone 16 Pro]'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '还有哪些来源能确认这些参数？',
      );
      await tester.pumpAndSettle();

      expect(find.text('还有哪些来源能确认这些参数？'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('chat_send')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}

RuntimeAgentState _secondScreenState() {
  return RuntimeAgentState.fromJson(const {
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      {
        'turn_id': 'turn-user-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '查一下最近 Apple 发布会有哪些新产品，给我带来源。',
        'created_at_ms': 1778595480000,
      },
      {
        'turn_id': 'turn-assistant-1',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': '根据 2024 年 9 月的发布会记录，Apple 推出了一系列核心产品更新：\n\n'
            '- **iPhone 16 & 16 Pro 系列**：搭载全新 A18/A18 Pro 芯片，全系配备“相机控制”按键 [1]。\n'
            '- **Apple Watch Series 10**：采用更轻薄的设计和尺寸更大的广视角 OLED 显示屏 [2]。\n'
            '- **AirPods 4**：分为基础版和支持主动降噪的版本 [1]。',
        'web_research_drafts': [
          {
            'query': 'Apple September event products',
            'summary':
                'Apple announced iPhone 16, Apple Watch Series 10, and AirPods 4.',
            'citations': [
              {
                'title': 'iPhone 16 and iPhone 16 Plus - Apple',
                'url': 'https://www.apple.com/iphone-16/',
                'domain': 'apple.com',
                'fetched_at_ms': 1778595600000,
              },
              {
                'title': 'Apple Event: Everything Announced',
                'url': 'https://www.macrumors.com/guide/apple-event-recap/',
                'domain': 'macrumors.com',
                'fetched_at_ms': 1778595600000,
              },
            ],
          },
        ],
        'tool_trace': {
          'skill': 'web-research',
          'postprocess': 'skill_result_response',
          'current_facts': 'web-research required',
        },
        'created_at_ms': 1778595600000,
      },
      {
        'turn_id': 'turn-user-2',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'user',
        'content': '介绍一下新的手机产品参数。',
        'created_at_ms': 1778595660000,
      },
      {
        'turn_id': 'turn-assistant-2',
        'conversation_id': 'loop_home',
        'vault_id': 'uid_1',
        'role': 'assistant',
        'content': '以下是 iPhone 16 Pro 的核心参数摘要：\n\n'
            '| 参数 | 摘要 |\n'
            '| --- | --- |\n'
            '| Chipset | A18 Pro，6-core GPU |\n'
            '| Camera | 48MP Fusion, 48MP UW, 12MP 5x Telephoto |\n'
            '| Display | 6.3 / 6.9 英寸 ProMotion OLED |',
        'citations_json':
            '{"direct_sources":[{"id":"src-1","href":"https://www.apple.com/iphone-16-pro/","source_type":"web_research","label":"apple.com","source_type_label":"Web research","scope_label":"Runtime web research","confidence_label":"Cited source","title":"iPhone 16 Pro - Apple","snippet":"A18 Pro, camera and display details.","created_at_ms":1778595720000},{"id":"src-2","href":"https://www.apple.com/newsroom/","source_type":"web_research","label":"apple.com","source_type_label":"Web research","scope_label":"Runtime web research","confidence_label":"Cited source","title":"Apple Event newsroom","snippet":"Phone launch context.","created_at_ms":1778595720000}]}',
        'tool_trace': {
          'skill': 'web-research',
          'trace_id': 'SRCH-2026-05-12',
          'context_snapshot_id': 'CTX-9921',
          'postprocess': 'skill_result_response',
          'current_facts': 'web-research required',
          'extracted_evidence':
              'MATCH: term[iPhone 16 Pro] ATTR[Chip] VALUE[A18 Pro] CONF[0.99]',
        },
        'created_at_ms': 1778595720000,
      },
    ],
    'working_set_records': [],
    'tasks': [],
    'memory_records': [],
    'recurring_reminder_rules': [],
    'approval_items': [],
    'recent_entity_refs': [],
    'latest_context_snapshot': {
      'id': 'CTX-9921',
      'generated_at_ms': 1778595720000,
      'packet': {
        'recent_turns': 'previous Apple launch web-research result',
        'context_status': 'follow-up resolved from recent_turns',
      },
    },
    'audit_refs': [
      {'id': 'SRCH-2026-05-12'},
    ],
  });
}

final class _FakeRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  const _FakeRuntimeAgentStateRepository(this.state);

  final RuntimeAgentState state;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    return state;
  }
}

final class _CloudAuthController extends ChangeNotifier
    implements CloudAuthController {
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
