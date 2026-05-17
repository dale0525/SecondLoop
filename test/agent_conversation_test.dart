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

import 'test_backend.dart';
import 'test_i18n.dart';

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
                    supportsBiometricUnlock: false,
                    supportsAudioRecording: true,
                    supportsDesktopDrop: true,
                    supportsDesktopBootSettings: true,
                    supportsCameraCapture: false,
                    usesCloudSessionModel: false,
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: SubscriptionScope(
                      controller: _SubscriptionController(
                        SubscriptionStatus.entitled,
                      ),
                      child: const AppShell(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

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

        expect(backend.askAiStreamCalls, 1);
        expect(backend.lastAskedQuestion, '我今晚 8 点要处理护照续期，请先帮我判断下一步');
        expect(
            find.byKey(const ValueKey('approval_preview_card')), findsNothing);
        expect(find.textContaining('AI 已收到'), findsOneWidget);
        expect(
            backend.insertedRoles, containsAllInOrder(['user', 'assistant']));
        expect(backend.upsertTodoCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'agent conversation renders assistant action blocks as user-facing markdown',
    (tester) async {
      final backend = _ActionBlockBackend();
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
                    supportsBiometricUnlock: false,
                    supportsAudioRecording: true,
                    supportsDesktopDrop: true,
                    supportsDesktopBootSettings: true,
                    supportsCameraCapture: false,
                    usesCloudSessionModel: false,
                  ),
                  child: SessionScope(
                    sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                    lock: () {},
                    child: SubscriptionScope(
                      controller: _SubscriptionController(
                        SubscriptionStatus.entitled,
                      ),
                      child: const AppShell(),
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

        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(find.text('提醒预览：'), findsOneWidget);
        expect(find.textContaining('secondloop_actions'), findsNothing);
        expect(find.textContaining('"suggestions"'), findsNothing);
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
                    supportsBiometricUnlock: false,
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
                    supportsBiometricUnlock: false,
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
                    supportsBiometricUnlock: false,
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
    'agent conversation hides stream metadata and reports empty AI response',
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
                    supportsBiometricUnlock: false,
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
        expect(backend.askAiStreamCalls, 1);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'agent conversation turns stream error sentinel into user visible failure',
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
                    supportsBiometricUnlock: false,
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
        expect(backend.askAiStreamCalls, 1);
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
                    supportsBiometricUnlock: false,
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
    'managed pro conversation persists runtime-created tasks into app state',
    (tester) async {
      final backend = _RuntimeTaskCreationBackend();
      final sender = _FakeRuntimeConversationSender(
        result: SecretaryRuntimeConversationResult.fromJson(const {
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
        }),
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
                  supportsBiometricUnlock: false,
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
      expect(backend.upsertTodoCalls, 1);
      final todos = await backend.listTodos(
        Uint8List.fromList(List<int>.filled(32, 1)),
      );
      expect(todos.single.title, '完成周报');
      expect(todos.single.status, 'open');
      expect(todos.single.sourceEntryId, 'm1');
      expect(find.textContaining('好的，已为您创建任务'), findsOneWidget);
    },
  );

  testWidgets(
    'agent conversation shows reasoning temporarily until answer starts',
    (tester) async {
      final backend = _ControlledReasoningBackend();
      await _pumpAgentConversation(tester, backend);
      await _sendAgentMessage(tester);

      backend.stream.add(
        '$_askAiReasoningPrefix{"text":"I should inspect the local context."}',
      );
      await tester.pump();
      expect(
          find.byKey(const ValueKey('agent_thinking_panel')), findsOneWidget);
      expect(find.textContaining('I should inspect the local context.'),
          findsOneWidget);

      backend.stream.add('The next step is to book the appointment.');
      await tester.pump();
      expect(find.textContaining('I should inspect the local context.'),
          findsNothing);
      expect(find.textContaining('The next step is to book the appointment.'),
          findsOneWidget);
      expect(find.textContaining('Final answer'), findsNothing);
    },
  );

  testWidgets(
    'agent conversation does not treat reasoning-only stream as answer',
    (tester) async {
      final backend = _ControlledReasoningBackend();
      await _pumpAgentConversation(tester, backend);
      await _sendAgentMessage(tester);

      backend.stream.add(
        '$_askAiReasoningPrefix{"text":"I should inspect the local context."}',
      );
      await tester.pump();
      expect(
          find.byKey(const ValueKey('agent_thinking_panel')), findsOneWidget);
      expect(find.textContaining('I should inspect the local context.'),
          findsOneWidget);

      await backend.stream.close();
      await tester.pumpAndSettle();
      expect(find.textContaining('I should inspect the local context.'),
          findsNothing);
      expect(find.text('Ask AI failed. Please try again.'), findsOneWidget);
      expect(find.textContaining('Final answer'), findsNothing);
    },
  );

  testWidgets(
    'agent conversation ignores unknown stream control chunks',
    (tester) async {
      final backend = _ControlledReasoningBackend();
      await _pumpAgentConversation(tester, backend);
      await _sendAgentMessage(tester);

      backend.stream.add(
        '$_askAiReasoningPrefix{"text":"I should inspect the local context."}',
      );
      await tester.pump();
      expect(find.textContaining('I should inspect the local context.'),
          findsOneWidget);

      backend.stream.add('\u001eSL_UNKNOWN\u001e{"text":"do not render"}');
      await tester.pump();
      expect(find.textContaining('SL_UNKNOWN'), findsNothing);
      expect(find.textContaining('do not render'), findsNothing);
      expect(find.textContaining('I should inspect the local context.'),
          findsOneWidget);

      backend.stream.add('The next step is to book the appointment.');
      await tester.pump();
      expect(find.textContaining('I should inspect the local context.'),
          findsNothing);
      expect(find.textContaining('The next step is to book the appointment.'),
          findsOneWidget);
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

Future<void> _pumpAgentConversation(
  WidgetTester tester,
  TestAppBackend backend,
) async {
  await tester.binding.setSurfaceSize(const Size(1012, 701));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrapWithI18n(MaterialApp(
      home: AppBackendScope(
    backend: backend,
    child: AppPlatformCapabilityScope(
      capabilities: const AppPlatformCapabilities(
        supportsDesktopHotkey: true,
        supportsBiometricUnlock: false,
        supportsAudioRecording: true,
        supportsDesktopDrop: true,
        supportsDesktopBootSettings: true,
        supportsCameraCapture: false,
        usesCloudSessionModel: false,
      ),
      child: SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: SubscriptionScope(
          controller: _SubscriptionController(SubscriptionStatus.entitled),
          child: const AppShell(),
        ),
      ),
    ),
  ))));
  await tester.pumpAndSettle();
}

Future<void> _sendAgentMessage(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('chat_input')),
    'Please help me decide the next step.',
  );
  await tester.pump();
  tester
      .widget<FilledButton>(
        find.byKey(const ValueKey('chat_send')),
      )
      .onPressed!();
  await tester.pump();
}

final class _TrackingBackend extends TestAppBackend {
  int insertMessageCalls = 0;
  int askAiStreamCalls = 0;
  int upsertTodoCalls = 0;
  String? lastAskedQuestion;
  final List<String> insertedRoles = <String>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    insertMessageCalls += 1;
    insertedRoles.add(role);
    return super.insertMessage(
      key,
      conversationId,
      role: role,
      content: content,
    );
  }

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    askAiStreamCalls += 1;
    lastAskedQuestion = question;
    await insertMessage(
      key,
      conversationId,
      role: 'user',
      content: question,
    );
    const answer = 'AI 已收到，我会先检查现有信息，再给出可确认的下一步。';
    yield answer;
    await insertMessage(
      key,
      conversationId,
      role: 'assistant',
      content: answer,
    );
  }

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    upsertTodoCalls += 1;
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
  }
}

final class _ControlledReasoningBackend extends TestAppBackend {
  final stream = StreamController<String>();
  int askAiStreamCalls = 0;
  String? lastAskedQuestion;

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    askAiStreamCalls += 1;
    lastAskedQuestion = question;
    return stream.stream;
  }
}

final class _MetaOnlyBackend extends TestAppBackend {
  int askAiStreamCalls = 0;

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    askAiStreamCalls += 1;
    yield '$_askAiMetaPrefix{"type":"cloud_request_id","request_id":"req_staging_1"}';
  }
}

final class _ActionBlockBackend extends _TrackingBackend {
  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    askAiStreamCalls += 1;
    lastAskedQuestion = question;
    await insertMessage(
      key,
      conversationId,
      role: 'user',
      content: question,
    );
    const answer = '''
好的，我已经为您准备好了护照续期的提醒预览：

**提醒预览：**
* **事项名称**：处理护照续期
* **提醒时间**：今晚 20:00

```secondloop_actions
{"version":1,"suggestions":[{"type":"todo","title":"处理护照续期","when":"今晚 8 点"}]}
```
''';
    yield answer;
    await insertMessage(
      key,
      conversationId,
      role: 'assistant',
      content: answer,
    );
  }
}

final class _StreamErrorBackend extends TestAppBackend {
  int askAiStreamCalls = 0;

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    askAiStreamCalls += 1;
    yield '$_askAiMetaPrefix{"type":"cloud_request_id","request_id":"req_staging_2"}';
    yield '${_askAiErrorPrefix}cloud-gateway request failed: HTTP 500';
  }
}

final class _EmbeddingQuotaFailureBackend extends TestAppBackend {
  final List<int> cloudTopKCalls = <int>[];

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async* {
    cloudTopKCalls.add(topK);
    yield '${_askAiErrorPrefix}cloud-gateway embeddings request failed: HTTP 429 {"error":"embeddings_token_quota_exceeded"}';
  }
}

final class _RuntimeTaskCreationBackend extends TestAppBackend {
  final Map<String, Todo> _todos = <String, Todo>{};
  int cloudStreamCalls = 0;
  int upsertTodoCalls = 0;

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async* {
    cloudStreamCalls += 1;
    throw StateError('managed_pro_should_use_secretary_runtime');
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    return _todos.values.toList(growable: false);
  }

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    upsertTodoCalls += 1;
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todos[id] = todo;
    return todo;
  }
}

final class _FakeRuntimeConversationSender
    implements ChatRuntimeConversationSender {
  _FakeRuntimeConversationSender({required this.result});

  final SecretaryRuntimeConversationResult result;
  final List<String> sentMessages = <String>[];
  final List<String> vaultIds = <String>[];
  final List<String> conversationIds = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    vaultIds.add(vaultId);
    conversationIds.add(conversationId);
    sentMessages.add(message);
    return result;
  }
}

final class _ThrowingRuntimeConversationSender
    implements ChatRuntimeConversationSender {
  _ThrowingRuntimeConversationSender(this.error);

  final Object error;
  final List<String> sentMessages = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    sentMessages.add(message);
    throw error;
  }
}

final class _SubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _SubscriptionController(this.status);

  @override
  final SubscriptionStatus status;
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
