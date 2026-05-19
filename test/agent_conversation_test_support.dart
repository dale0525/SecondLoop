part of 'agent_conversation_test.dart';

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

Future<void> _pumpManagedProAgentConversation(
  WidgetTester tester,
  TestAppBackend backend,
  ChatRuntimeConversationSender sender, {
  RuntimeAgentStateRepository? runtimeAgentStateRepository,
}) async {
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
                    runtimeAgentStateRepository: runtimeAgentStateRepository,
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

final class _FakeRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _FakeRuntimeAgentStateRepository({
    RuntimeAgentState? initialState,
  }) : state = initialState ??
            RuntimeAgentState.empty(
              vaultId: 'uid_1',
              conversationId: 'loop_home',
            );

  RuntimeAgentState state;
  final List<(String, String)> requests = <(String, String)>[];

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
  }) async {
    requests.add((vaultId, conversationId));
    return state;
  }
}

RuntimeAgentState _runtimeAgentStateFromResult(
  SecretaryRuntimeConversationResult result, {
  required String vaultId,
  required String conversationId,
  required String userMessage,
}) {
  final taskRecords = <Map<String, Object?>>[];
  for (final mutation in result.metadata.appliedMutations) {
    if (mutation['entity_type'] != 'task') continue;
    final record = mutation['record'];
    if (record is Map) {
      taskRecords.add(
        record.map((key, value) => MapEntry('$key', value as Object?)),
      );
    }
  }
  return RuntimeAgentState.fromJson({
    'vault_id': vaultId,
    'conversation_id': conversationId,
    'conversation_turns': [
      {
        'turn_id': 'turn-user-1',
        'conversation_id': conversationId,
        'vault_id': vaultId,
        'role': 'user',
        'content': userMessage,
        'created_at_ms': 1700000000000,
      },
      {
        'turn_id': 'turn-assistant-1',
        'conversation_id': conversationId,
        'vault_id': vaultId,
        'role': 'assistant',
        'content': result.assistantContent,
        'web_research_drafts': result.metadata.webResearchDrafts,
        'created_at_ms': 1700000000001,
      },
    ],
    'working_set_records': taskRecords,
    'tasks': taskRecords,
    'memory_records': const <Map<String, Object?>>[],
    'recurring_reminder_rules': const <Map<String, Object?>>[],
    'approval_items': result.metadata.approvalItems
        .map(
          (item) => {
            'id': item.id,
            'task_id': item.taskId,
            'title': item.title,
            'kind': item.kind,
            'recurring_rule_id': item.recurringRuleId,
            'editable_fields': item.editableFields,
            'version': item.version,
            if (item.record != null) 'record': item.record,
          },
        )
        .toList(growable: false),
    'recent_entity_refs': const <Map<String, Object?>>[],
    'latest_context_snapshot': null,
    'audit_refs': const <Map<String, Object?>>[],
  });
}

final class _FakeRuntimeConversationSender
    implements ChatRuntimeConversationSender {
  _FakeRuntimeConversationSender({
    required this.result,
    this.onSend,
  });

  final SecretaryRuntimeConversationResult result;
  final void Function(
    String vaultId,
    String conversationId,
    String message,
    SecretaryRuntimeConversationResult result,
  )? onSend;
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
    onSend?.call(vaultId, conversationId, message, result);
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
