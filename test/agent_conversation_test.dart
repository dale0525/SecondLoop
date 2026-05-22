import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/features/chat/chat_markdown_rich_rendering.dart';
import 'package:secondloop/features/inbox/inbox_page.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

part 'agent_conversation_test_support.dart';

const _askAiMetaPrefix = '\u001eSL_META\u001e';
const _askAiErrorPrefix = '\u001eSL_ERROR\u001e';
const _askAiReasoningPrefix = '\u001eSL_REASONING\u001e';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'empty production conversation does not show demo content',
    (tester) async {
      await _pumpAgentConversation(tester, TestAppBackend());

      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.text("Here's your brief for today."), findsNothing);
      expect(find.text('2 priorities due today'), findsNothing);
      expect(find.text('passport-scan.pdf'), findsNothing);
      expect(find.byKey(const ValueKey('approval_preview_card')), findsNothing);
    },
  );

  testWidgets('agent conversation scrolls to latest message on launch',
      (tester) async {
    final messages = List<Message>.generate(30, (index) {
      final number = index + 1;
      return Message(
        id: 'm$number',
        conversationId: 'loop_home',
        role: index.isEven ? 'user' : 'assistant',
        content: 'Launch scroll marker $number',
        createdAtMs: number,
        isMemory: true,
      );
    });

    await _pumpAgentConversation(
      tester,
      TestAppBackend(initialMessages: messages),
    );

    expect(find.text('Launch scroll marker 30'), findsOneWidget);
    expect(find.text('Launch scroll marker 1'), findsNothing);
  });

  testWidgets(
    'agent conversation sends through AI instead of local review demo',
    (tester) async {
      final backend = _TrackingBackend();
      final result = SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-send-1',
        'conversation_id': 'loop_home',
        'assistant': {
          'content': 'AI 已收到，我会先检查现有信息，再给出可确认的下一步。',
        },
        'metadata': {
          'run_id': 'run-send-1',
          'turn_id': 'turn-send-1',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'response_type': 'assistant_message',
          'run_status': 'completed',
          'approval_required': false,
        },
      });
      final repository = _FakeRuntimeAgentStateRepository();
      final sender = _FakeRuntimeConversationSender(
        result: result,
        onSend: (vaultId, conversationId, message, result) {
          repository.state = _runtimeAgentStateFromResult(
            result,
            vaultId: vaultId,
            conversationId: conversationId,
            userMessage: message,
          );
        },
      );
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await _pumpManagedProAgentConversation(
          tester,
          backend,
          sender,
          runtimeAgentStateRepository: repository,
        );

        expect(
          find.byKey(const ValueKey('conversation_context_rail')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent_conversation_workspace')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('chat_input')),
          '我今晚 8 点要处理护照续期，请先帮我判断下一步',
        );
        await tester.pumpAndSettle();
        final input = tester.widget<EditableText>(find.byType(EditableText));
        expect(input.controller.text, '我今晚 8 点要处理护照续期，请先帮我判断下一步');

        expect(find.byKey(const ValueKey('chat_ask_ai')), findsNothing);
        final sendButton = tester
            .widget<FilledButton>(find.byKey(const ValueKey('chat_send')));
        expect(sendButton.onPressed, isNotNull);

        sendButton.onPressed!();
        await tester.pumpAndSettle();

        expect(backend.askAiStreamCalls, 0);
        expect(sender.sentMessages, ['我今晚 8 点要处理护照续期，请先帮我判断下一步']);
        expect(
            find.byKey(const ValueKey('approval_preview_card')), findsNothing);
        expect(find.textContaining('AI 已收到'), findsOneWidget);
        expect(backend.insertedRoles, isEmpty);
        expect(backend.upsertTodoCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'agent conversation renders assistant action blocks as user-facing markdown',
    (tester) async {
      final backend = _TrackingBackend();
      final result = SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-action-1',
        'conversation_id': 'loop_home',
        'assistant': {
          'content': '''
好的，我已经为您准备好了护照续期的提醒预览：

**提醒预览：**
* **事项名称**：处理护照续期
* **提醒时间**：今晚 20:00

```secondloop_actions
{"version":1,"suggestions":[{"type":"todo","title":"处理护照续期","when":"今晚 8 点"}]}
```
''',
        },
        'metadata': {
          'run_id': 'run-action-1',
          'turn_id': 'turn-action-1',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'response_type': 'assistant_message',
          'run_status': 'completed',
          'approval_required': false,
        },
      });
      final repository = _FakeRuntimeAgentStateRepository();
      final sender = _FakeRuntimeConversationSender(
        result: result,
        onSend: (vaultId, conversationId, message, result) {
          repository.state = _runtimeAgentStateFromResult(
            result,
            vaultId: vaultId,
            conversationId: conversationId,
            userMessage: message,
          );
        },
      );
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await _pumpManagedProAgentConversation(
          tester,
          backend,
          sender,
          runtimeAgentStateRepository: repository,
        );

        await tester.enterText(
          find.byKey(const ValueKey('chat_input')),
          '我今晚 8 点要处理护照续期，请生成一个提醒预览，但先不要直接保存',
        );
        await tester.pumpAndSettle();
        final sendButton = tester
            .widget<FilledButton>(find.byKey(const ValueKey('chat_send')));

        sendButton.onPressed!();
        await tester.pumpAndSettle();

        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(find.text('提醒预览：'), findsOneWidget);
        expect(find.textContaining('secondloop_actions'), findsNothing);
        expect(find.textContaining('"suggestions"'), findsNothing);
        expect(backend.askAiStreamCalls, 0);
        expect(backend.upsertTodoCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'agent conversation surfaces assistant action suggestions',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await tester.binding.setSurfaceSize(const Size(1012, 701));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          wrapWithI18n(
            MaterialApp(
              home: AppBackendScope(
                backend: TestAppBackend(
                  initialMessages: const <Message>[
                    Message(
                      id: 'assistant-actions-1',
                      conversationId: 'loop_home',
                      role: 'assistant',
                      content: '''
我准备了一个候选提醒。

```secondloop_actions
{"version":1,"suggestions":[{"type":"todo","title":"处理护照续期","when":"今晚 8 点"}]}
```
''',
                      createdAtMs: 1,
                      isMemory: false,
                    ),
                  ],
                ),
                child: AppPlatformCapabilityScope(
                  capabilities: const AppPlatformCapabilities(
                    supportsDesktopHotkey: true,
                    supportsAudioRecording: true,
                    supportsDesktopDrop: true,
                    supportsDesktopBootSettings: true,
                    supportsCameraCapture: false,
                    usesCloudSessionModel: false,
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: const AppShell(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('assistant_message_footer_suggestions')),
          findsOneWidget,
        );
        expect(find.text('处理护照续期 (今晚 8 点)'), findsOneWidget);
        expect(find.textContaining('secondloop_actions'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'agent conversation renders assistant citations and evidence footer',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await tester.binding.setSurfaceSize(const Size(1012, 701));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          wrapWithI18n(
            MaterialApp(
              home: AppBackendScope(
                backend: TestAppBackend(
                  initialMessages: const <Message>[
                    Message(
                      id: 'assistant-citation-1',
                      conversationId: 'loop_home',
                      role: 'assistant',
                      content:
                          '护照续期已在历史记录中出现过。[历史](secondloop://message/history-1)',
                      createdAtMs: 1,
                      isMemory: false,
                      citationsJson:
                          '{"direct_sources":[{"id":"message:history-1","href":"secondloop://message/history-1","source_type":"message","label":"History","source_type_label":"Chat message","scope_label":"This thread","confidence_label":"High relevance","title":"护照续期记录","snippet":"今晚 8 点处理护照续期。","created_at_ms":1,"updated_at_ms":1}]}',
                    ),
                  ],
                ),
                child: AppPlatformCapabilityScope(
                  capabilities: const AppPlatformCapabilities(
                    supportsDesktopHotkey: true,
                    supportsAudioRecording: true,
                    supportsDesktopDrop: true,
                    supportsDesktopBootSettings: true,
                    supportsCameraCapture: false,
                    usesCloudSessionModel: false,
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: const AppShell(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('assistant_message_footer_evidence')),
          findsOneWidget,
        );
        expect(find.text('1 sources'), findsOneWidget);
        expect(find.text('[1]', findRichText: true), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'agent conversation renders assistant rich markdown formats',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await tester.binding.setSurfaceSize(const Size(1012, 701));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          wrapWithI18n(
            MaterialApp(
              home: AppBackendScope(
                backend: TestAppBackend(
                  initialMessages: const <Message>[
                    Message(
                      id: 'assistant-rich-1',
                      conversationId: 'loop_home',
                      role: 'assistant',
                      content: r'''
这是一个带公式、脑图和历史引用的回答：$e^{i\pi}+1=0$

$$\int_0^1 x^2 \mathrm{d}x$$

```markmap
# 护照计划
## 预约
## 材料
```

secondloop://message/history-rich-1
''',
                      createdAtMs: 1,
                      isMemory: false,
                      citationsJson:
                          '{"direct_sources":[{"id":"message:history-rich-1","href":"secondloop://message/history-rich-1","source_type":"message","label":"History","source_type_label":"Chat message","scope_label":"This thread","confidence_label":"High relevance","title":"历史记录","snippet":"护照续期计划。","created_at_ms":1,"updated_at_ms":1}]}',
                    ),
                  ],
                ),
                child: AppPlatformCapabilityScope(
                  capabilities: const AppPlatformCapabilities(
                    supportsDesktopHotkey: true,
                    supportsAudioRecording: true,
                    supportsDesktopDrop: true,
                    supportsDesktopBootSettings: true,
                    supportsCameraCapture: false,
                    usesCloudSessionModel: false,
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: const AppShell(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ChatMarkdownLatexInline), findsOneWidget);
        expect(find.byType(ChatMarkdownLatexBlock), findsOneWidget);
        expect(find.byType(ChatMarkdownMarkmap), findsOneWidget);
        expect(find.text('[1]', findRichText: true), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'agent conversation setup failure does not read local stream metadata',
    (tester) async {
      final backend = _MetaOnlyBackend();
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await tester.binding.setSurfaceSize(const Size(1012, 701));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          wrapWithI18n(
            MaterialApp(
              home: AppBackendScope(
                backend: backend,
                child: AppPlatformCapabilityScope(
                  capabilities: const AppPlatformCapabilities(
                    supportsDesktopHotkey: true,
                    supportsAudioRecording: true,
                    supportsDesktopDrop: true,
                    supportsDesktopBootSettings: true,
                    supportsCameraCapture: false,
                    usesCloudSessionModel: false,
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: const AppShell(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('chat_input')),
          '我今晚 8 点要处理护照续期，请生成一个提醒预览，但先不要直接保存',
        );
        await tester.pumpAndSettle();
        final sendButton = tester
            .widget<FilledButton>(find.byKey(const ValueKey('chat_send')));

        sendButton.onPressed!();
        await tester.pumpAndSettle();

        expect(find.textContaining('SL_META'), findsNothing);
        expect(find.textContaining('cloud_request_id'), findsNothing);
        expect(find.textContaining('req_staging_1'), findsNothing);
        expect(find.text('Ask AI failed. Please try again.'), findsOneWidget);
        expect(find.textContaining('护照续期'), findsOneWidget);
        expect(backend.askAiStreamCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'agent conversation setup failure does not read local stream errors',
    (tester) async {
      final backend = _StreamErrorBackend();
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await tester.binding.setSurfaceSize(const Size(1012, 701));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          wrapWithI18n(
            MaterialApp(
              home: AppBackendScope(
                backend: backend,
                child: AppPlatformCapabilityScope(
                  capabilities: const AppPlatformCapabilities(
                    supportsDesktopHotkey: true,
                    supportsAudioRecording: true,
                    supportsDesktopDrop: true,
                    supportsDesktopBootSettings: true,
                    supportsCameraCapture: false,
                    usesCloudSessionModel: false,
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: const AppShell(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('chat_input')),
          '我今晚 8 点要处理护照续期，请生成一个提醒预览，但先不要直接保存',
        );
        await tester.pumpAndSettle();
        final sendButton = tester
            .widget<FilledButton>(find.byKey(const ValueKey('chat_send')));

        sendButton.onPressed!();
        await tester.pumpAndSettle();

        expect(find.textContaining('SL_ERROR'), findsNothing);
        expect(find.textContaining('HTTP 500'), findsNothing);
        expect(find.text('Ask AI failed. Please try again.'), findsOneWidget);
        expect(backend.askAiStreamCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'managed pro runtime failures do not fall back to retrieval stream',
    (tester) async {
      final backend = _EmbeddingQuotaFailureBackend();
      final sender = _ThrowingRuntimeConversationSender(
        StateError('runtime_quota_unavailable'),
      );
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await tester.binding.setSurfaceSize(const Size(1012, 701));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          wrapWithI18n(
            MaterialApp(
              home: AppBackendScope(
                backend: backend,
                child: AppPlatformCapabilityScope(
                  capabilities: const AppPlatformCapabilities(
                    supportsDesktopHotkey: true,
                    supportsAudioRecording: true,
                    supportsDesktopDrop: true,
                    supportsDesktopBootSettings: true,
                    supportsCameraCapture: false,
                    usesCloudSessionModel: false,
                  ),
                  child: CloudAuthScope(
                    controller: _CloudAuthController(),
                    gatewayConfig: const CloudGatewayConfig(
                      baseUrl: 'https://gateway.example.test',
                      modelName: 'cloud',
                    ),
                    child: SessionScope(
                      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                      lock: () {},
                      child: SubscriptionScope(
                        controller: _SubscriptionController(
                          SubscriptionStatus.entitled,
                        ),
                        child: AgentConversationPage(
                          conversation: const Conversation(
                            id: 'loop_home',
                            title: 'Loop',
                            createdAtMs: 0,
                            updatedAtMs: 0,
                          ),
                          isTabActive: true,
                          runtimeConversationSender: sender,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('chat_input')),
          '我今晚 8 点要处理护照续期，请生成一个提醒预览，但先不要直接保存',
        );
        await tester.pumpAndSettle();
        final sendButton = tester
            .widget<FilledButton>(find.byKey(const ValueKey('chat_send')));

        sendButton.onPressed!();
        await tester.pumpAndSettle();

        expect(sender.sentMessages, [
          '我今晚 8 点要处理护照续期，请生成一个提醒预览，但先不要直接保存',
        ]);
        expect(backend.cloudTopKCalls, isEmpty);
        expect(find.textContaining('SL_ERROR'), findsNothing);
        expect(find.textContaining('runtime_quota_unavailable'), findsNothing);
        expect(find.text('Ask AI failed. Please try again.'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'managed pro conversation does not persist runtime-created tasks locally',
    (tester) async {
      final backend = _RuntimeTaskCreationBackend();
      final result = SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-qa-chat-01',
        'conversation_id': 'loop_home',
        'assistant': {'content': '好的，已为您创建任务：完成周报。'},
        'metadata': {
          'run_id': 'run-qa-chat-01',
          'turn_id': 'turn-qa-chat-01',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'response_type': 'task_created',
          'run_status': 'completed',
          'approval_required': false,
          'applied_mutations': [
            {
              'entity_type': 'task',
              'mutation_type': 'create',
              'status': 'applied',
              'record_id': 'task-qa-chat-01',
              'record': {
                'id': 'task-qa-chat-01',
                'title': '完成周报',
                'status': 'todo',
              },
            },
          ],
        },
      });
      final repository = _FakeRuntimeAgentStateRepository();
      final sender = _FakeRuntimeConversationSender(
        result: result,
        onSend: (vaultId, conversationId, message, result) {
          repository.state = _runtimeAgentStateFromResult(
            result,
            vaultId: vaultId,
            conversationId: conversationId,
            userMessage: message,
          );
        },
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: AppPlatformCapabilityScope(
                capabilities: const AppPlatformCapabilities(
                  supportsDesktopHotkey: true,
                  supportsAudioRecording: true,
                  supportsDesktopDrop: true,
                  supportsDesktopBootSettings: true,
                  supportsCameraCapture: false,
                  usesCloudSessionModel: false,
                ),
                child: CloudAuthScope(
                  controller: _CloudAuthController(),
                  gatewayConfig: const CloudGatewayConfig(
                    baseUrl: 'https://gateway.example.test',
                    modelName: 'cloud',
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: SubscriptionScope(
                      controller: _SubscriptionController(
                        SubscriptionStatus.entitled,
                      ),
                      child: AgentConversationPage(
                        conversation: const Conversation(
                          id: 'loop_home',
                          title: 'Loop',
                          createdAtMs: 0,
                          updatedAtMs: 0,
                        ),
                        isTabActive: true,
                        runtimeConversationSender: sender,
                        runtimeAgentStateRepository: repository,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '帮我创建一个任务：完成周报。',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(sender.sentMessages, ['帮我创建一个任务：完成周报。']);
      expect(sender.vaultIds, ['uid_1']);
      expect(sender.conversationIds, ['loop_home']);
      expect(backend.cloudStreamCalls, 0);
      expect(backend.upsertTodoCalls, 0);
      final todos = await backend.listTodos(
        Uint8List.fromList(List<int>.filled(32, 1)),
      );
      expect(todos, isEmpty);
      expect(find.textContaining('好的，已为您创建任务'), findsOneWidget);
    },
  );

  testWidgets(
    'managed pro conversation renders runtime web research citations',
    (tester) async {
      final backend = _RuntimeTaskCreationBackend();
      final result = SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-qa-chat-05',
        'conversation_id': 'loop_home',
        'assistant': {
          'content':
              'Apple 发布了 iPhone 17。[Apple Newsroom](https://www.apple.com/newsroom/)',
        },
        'metadata': {
          'run_id': 'run-qa-chat-05',
          'turn_id': 'turn-qa-chat-05',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'response_type': 'assistant_message',
          'run_status': 'completed',
          'approval_required': false,
          'web_research_drafts': [
            {
              'query': 'Apple 今天的发布会发布了哪些产品？',
              'summary': 'Apple 发布了 iPhone 17。',
              'citations': [
                {
                  'title': 'Apple Newsroom',
                  'url': 'https://www.apple.com/newsroom/',
                  'domain': 'www.apple.com',
                  'fetched_at_ms': 1700000000000,
                },
              ],
            },
          ],
        },
      });
      final repository = _FakeRuntimeAgentStateRepository();
      final sender = _FakeRuntimeConversationSender(
        result: result,
        onSend: (vaultId, conversationId, message, result) {
          repository.state = _runtimeAgentStateFromResult(
            result,
            vaultId: vaultId,
            conversationId: conversationId,
            userMessage: message,
          );
        },
      );

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: AppPlatformCapabilityScope(
                capabilities: const AppPlatformCapabilities(
                  supportsDesktopHotkey: true,
                  supportsAudioRecording: true,
                  supportsDesktopDrop: true,
                  supportsDesktopBootSettings: true,
                  supportsCameraCapture: false,
                  usesCloudSessionModel: false,
                ),
                child: CloudAuthScope(
                  controller: _CloudAuthController(),
                  gatewayConfig: const CloudGatewayConfig(
                    baseUrl: 'https://gateway.example.test',
                    modelName: 'cloud',
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: SubscriptionScope(
                      controller: _SubscriptionController(
                        SubscriptionStatus.entitled,
                      ),
                      child: AgentConversationPage(
                        conversation: const Conversation(
                          id: 'loop_home',
                          title: 'Loop',
                          createdAtMs: 0,
                          updatedAtMs: 0,
                        ),
                        isTabActive: true,
                        runtimeConversationSender: sender,
                        runtimeAgentStateRepository: repository,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '查一下最近 Apple 发布会有哪些新产品，给我带来源。',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(sender.sentMessages, ['查一下最近 Apple 发布会有哪些新产品，给我带来源。']);
      expect(
        find.byKey(const ValueKey('assistant_message_footer_evidence')),
        findsOneWidget,
      );
      expect(find.text('1 sources'), findsOneWidget);
      expect(find.text('[1]', findRichText: true), findsOneWidget);
    },
  );

  testWidgets(
    'managed pro conversation localizes runtime media result labels',
    (tester) async {
      LocaleSettings.setLocale(AppLocale.zhCn);
      addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

      final backend = _RuntimeTaskCreationBackend();
      final result = SecretaryRuntimeConversationResult.fromJson(const {
        'run_id': 'run-qa-file-03',
        'conversation_id': 'loop_home',
        'assistant': {'content': '已整理这段音频。'},
        'metadata': {
          'run_id': 'run-qa-file-03',
          'turn_id': 'turn-assistant-1',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'response_type': 'assistant_message',
          'run_status': 'completed',
          'approval_required': false,
          'media_results': [
            {
              'id': 'media-audio-1',
              'filename': 'qa-meeting-audio.m4a',
              'media_type': 'audio',
              'transcript': 'Alice said the release can go out Friday.',
              'meeting_minutes': 'The release decision is ready.',
              'decisions': ['Ship on Friday'],
              'action_items': [
                {
                  'title': 'Send the release notes',
                  'owner': 'Mina',
                  'due': 'Tomorrow',
                },
              ],
              'citations': [
                {'title': 'qa-meeting-audio.m4a'},
              ],
            },
          ],
        },
      });
      final repository = _FakeRuntimeAgentStateRepository();
      final sender = _FakeRuntimeConversationSender(
        result: result,
        onSend: (vaultId, conversationId, message, result) {
          repository.state = _runtimeAgentStateFromResult(
            result,
            vaultId: vaultId,
            conversationId: conversationId,
            userMessage: message,
          );
        },
      );

      await _pumpManagedProAgentConversation(
        tester,
        backend,
        sender,
        runtimeAgentStateRepository: repository,
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat_input')),
        '请整理这段音频。',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('chat_send')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(find.text('转录'), findsOneWidget);
      expect(find.text('会议纪要'), findsOneWidget);
      expect(find.text('决策'), findsOneWidget);
      expect(find.text('行动项'), findsOneWidget);
      expect(find.text('来源'), findsOneWidget);
      expect(find.textContaining('负责人：Mina'), findsOneWidget);
      expect(find.textContaining('截止：Tomorrow'), findsOneWidget);
      expect(find.text('Transcript'), findsNothing);
      expect(find.text('Meeting minutes'), findsNothing);
      expect(find.text('Action items'), findsNothing);
    },
  );

  testWidgets(
    'agent conversation setup failure does not read local reasoning stream',
    (tester) async {
      final backend = _ControlledReasoningBackend();
      await _pumpAgentConversation(tester, backend);
      await _sendAgentMessage(tester);

      backend.stream.add(
        '$_askAiReasoningPrefix{"text":"I should inspect the local context."}',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent_thinking_panel')), findsNothing);
      expect(find.textContaining('I should inspect the local context.'),
          findsNothing);
      expect(find.text('Ask AI failed. Please try again.'), findsOneWidget);
      expect(backend.askAiStreamCalls, 0);
    },
  );

  testWidgets(
    'agent conversation setup failure does not treat local reasoning as answer',
    (tester) async {
      final backend = _ControlledReasoningBackend();
      await _pumpAgentConversation(tester, backend);
      await _sendAgentMessage(tester);

      backend.stream.add(
        '$_askAiReasoningPrefix{"text":"I should inspect the local context."}',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent_thinking_panel')), findsNothing);
      expect(find.textContaining('I should inspect the local context.'),
          findsNothing);

      expect(find.textContaining('I should inspect the local context.'),
          findsNothing);
      expect(find.text('Ask AI failed. Please try again.'), findsOneWidget);
      expect(find.textContaining('Final answer'), findsNothing);
      expect(backend.askAiStreamCalls, 0);
    },
  );

  testWidgets(
    'agent conversation setup failure ignores local stream control chunks',
    (tester) async {
      final backend = _ControlledReasoningBackend();
      await _pumpAgentConversation(tester, backend);
      await _sendAgentMessage(tester);

      backend.stream.add(
        '$_askAiReasoningPrefix{"text":"I should inspect the local context."}',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('I should inspect the local context.'),
          findsNothing);

      backend.stream.add('\u001eSL_UNKNOWN\u001e{"text":"do not render"}');
      await tester.pump();
      expect(find.textContaining('SL_UNKNOWN'), findsNothing);
      expect(find.textContaining('do not render'), findsNothing);
      expect(find.textContaining('I should inspect the local context.'),
          findsNothing);
      expect(backend.askAiStreamCalls, 0);
    },
  );

  testWidgets(
    'self managed conversation uses the same agent workspace',
    (tester) async {
      await _pumpAgentConversation(tester, TestAppBackend());

      expect(
        find.byKey(const ValueKey('agent_conversation_workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('conversation_context_rail')),
        findsOneWidget,
      );
    },
  );

  testWidgets('inbox conversations open the agent workspace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1012, 701));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: TestAppBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const Scaffold(body: InboxPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('conversation_loop_home')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent_conversation_workspace')),
      findsOneWidget,
    );
  });
}
