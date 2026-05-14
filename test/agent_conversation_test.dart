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
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/chat/chat_markdown_rich_rendering.dart';
import 'package:secondloop/features/inbox/inbox_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

const _askAiMetaPrefix = '\u001eSL_META\u001e';
const _askAiErrorPrefix = '\u001eSL_ERROR\u001e';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'empty production conversation does not show demo content',
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
                backend: TestAppBackend(),
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

        expect(find.text('No messages yet'), findsOneWidget);
        expect(find.text("Here's your brief for today."), findsNothing);
        expect(find.text('2 priorities due today'), findsNothing);
        expect(find.text('passport-scan.pdf'), findsNothing);
        expect(
            find.byKey(const ValueKey('approval_preview_card')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

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
    'managed pro reports retrieval quota errors without skipping retrieval',
    (tester) async {
      final backend = _EmbeddingQuotaFailureBackend();
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
                        child: const AppShell(),
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

        expect(backend.cloudTopKCalls, [10]);
        expect(find.textContaining('SL_ERROR'), findsNothing);
        expect(find.textContaining('embeddings_token_quota_exceeded'),
            findsNothing);
        expect(
          find.text(
            'AI could not retrieve context because cloud quota is unavailable. Please retry after quota is reset.',
          ),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'self managed conversation uses the same agent workspace',
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
                backend: TestAppBackend(),
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
          find.byKey(const ValueKey('agent_conversation_workspace')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('conversation_context_rail')),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
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
