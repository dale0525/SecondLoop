import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/features/settings/ai_ask_ai_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'TodoDetailPage hides follow-up section when backend lacks support',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);

    await tester.pumpWidget(_buildSubject(_UnsupportedBackend()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_suggestions_section')),
      findsNothing,
    );
    expect(find.text('Information follow-up'), findsNothing);
  });

  testWidgets('TodoDetailPage renders pending follow-up suggestions',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_suggestions_section')),
      findsOneWidget,
    );
    expect(find.text('Information follow-up'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.textContaining('未联网核实'), findsOneWidget);
  });

  testWidgets('TodoDetailPage applies pending follow-up suggestions',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_apply_pending')),
    );
    await tester.pumpAndSettle();

    expect(backend.appliedSuggestionIds, const <String>['f1']);
  });

  testWidgets('TodoDetailPage applying follow-up wakes sync listeners',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend();
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
    );
    var changeCount = 0;
    void onChange() => changeCount += 1;
    engine.changes.addListener(onChange);
    addTearDown(() {
      engine.changes.removeListener(onChange);
      engine.stop();
    });

    await tester.pumpWidget(_buildSubject(backend, syncEngine: engine));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_apply_pending')),
    );
    await tester.pumpAndSettle();

    expect(backend.appliedSuggestionIds, const <String>['f1']);
    expect(changeCount, greaterThan(0));
  });

  testWidgets('TodoDetailPage dismissing follow-up wakes sync listeners',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend();
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
    );
    var changeCount = 0;
    void onChange() => changeCount += 1;
    engine.changes.addListener(onChange);
    addTearDown(() {
      engine.changes.removeListener(onChange);
      engine.stop();
    });

    await tester.pumpWidget(_buildSubject(backend, syncEngine: engine));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_dismiss_pending')),
    );
    await tester.pumpAndSettle();

    expect(backend.dismissedSuggestionIds, const <String>['f1']);
    expect(changeCount, greaterThan(0));
  });

  testWidgets('TodoDetailPage renders applied follow-up suggestions',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(
      initialSuggestions: const <TodoFollowupSuggestion>[
        TodoFollowupSuggestion(
          id: 'f_applied',
          todoId: 't1',
          content: '已整理主流模型的定价与上下文窗口。',
          state: 'applied',
          source: 'cloud',
          generationMode: 'web_search',
          generationKey: 'gen_a',
          citationsJson: null,
          createdAtMs: 1,
          updatedAtMs: 1,
          dismissedAtMs: null,
          appliedActivityId: 'a1',
        ),
      ],
      initialActivities: const <TodoActivity>[
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'followup_information',
          fromStatus: null,
          toStatus: null,
          content: '已整理主流模型的定价与上下文窗口。',
          sourceMessageId: null,
          createdAtMs: 1,
        ),
      ],
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Web search'), findsOneWidget);
    expect(find.text('AI-collected information'), findsOneWidget);
  });

  testWidgets('TodoDetailPage derives citation domain from validated url',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(
      initialSuggestions: const <TodoFollowupSuggestion>[
        TodoFollowupSuggestion(
          id: 'f_domain',
          todoId: 't1',
          content: '已查询到最新信息。',
          state: 'pending',
          source: 'cloud',
          generationMode: 'web_search',
          generationKey: 'gen_domain',
          citationsJson:
              '[{"title":"Airport","url":"https://airport.example/flight","domain":"trusted.example"}]',
          createdAtMs: 1,
          updatedAtMs: 1,
          dismissedAtMs: null,
          appliedActivityId: null,
        ),
      ],
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    expect(find.textContaining('airport.example · Airport'), findsOneWidget);
    expect(find.textContaining('trusted.example · Airport'), findsNothing);
  });

  testWidgets('TodoDetailPage shows empty follow-up state', (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend =
        _Backend(initialSuggestions: const <TodoFollowupSuggestion>[]);

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    expect(find.text('No information follow-up yet.'), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage keeps pending follow-up until regenerate finishes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final completer = Completer<void>();
    final backend = _Backend(regenerateCompleter: completer);

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pump();

    expect(backend.dismissedSuggestionIds, isEmpty);
    expect(backend.enqueuedRegenerate, isTrue);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('TodoDetailPage regenerate wakes sync listeners immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend();
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
    );
    var changeCount = 0;
    void onChange() => changeCount += 1;
    engine.changes.addListener(onChange);
    addTearDown(() {
      engine.changes.removeListener(onChange);
      engine.stop();
    });

    await tester.pumpWidget(_buildSubject(backend, syncEngine: engine));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isTrue);
    expect(changeCount, greaterThan(0));
  });

  testWidgets(
      'TodoDetailPage disables manual regenerate while auto generation is active',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'auto_create',
        status: 'running',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isFalse);
  });

  testWidgets(
      'TodoDetailPage treats running manual regenerate as active generation',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'manual_regenerate',
        status: 'running',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: true,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('todo_detail_followup_generating_indicator')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isFalse);
  });

  testWidgets(
      'Product intent: TodoDetailPage auto failed follow-up job does not block manual regenerate',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'auto_create',
        status: 'failed',
        attempts: 1,
        nextRetryAtMs: 1,
        lastError: 'temporary error',
        includeManualFollowups: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isTrue);
  });

  testWidgets(
      'Product intent: TodoDetailPage failed follow-up job remains manually retryable',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'manual_regenerate',
        status: 'failed',
        attempts: 2,
        nextRetryAtMs: 1,
        lastError: 'temporary error',
        includeManualFollowups: true,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isTrue);
  });

  testWidgets('TodoDetailPage caches follow-up generation job future',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'auto_create',
        status: 'running',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(backend.getTodoFollowupGenerationJobCalls, 1);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.getTodoFollowupGenerationJobCalls, 1);
  });

  testWidgets('TodoDetailPage shows regenerate loading state', (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final completer = Completer<void>();
    final backend = _Backend(
      initialSuggestions: const <TodoFollowupSuggestion>[],
      regenerateCompleter: completer,
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_generating_indicator')),
      findsOneWidget,
    );
    expect(find.text('Generating information…'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_generating_indicator')),
      findsNothing,
    );
    expect(backend.enqueuedRegenerate, isTrue);
  });

  testWidgets(
      'TodoDetailPage regenerate opens AI settings when smart organization consent is disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': false,
    });
    _setLargeDisplay(tester);
    final backend = _Backend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isFalse);
    expect(find.byType(AiAskAiSettingsPage), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage regenerate opens AI settings when no automation route is configured',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(llmProfiles: const <LlmProfile>[]);

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isFalse);
    expect(find.byType(AiAskAiSettingsPage), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage regenerate opens AI settings when followup route decide throws',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _ThrowingLlmProfilesBackend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isFalse);
    expect(find.byType(AiAskAiSettingsPage), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'TodoDetailPage manual regenerate retries token read after warmup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(llmProfiles: const <LlmProfile>[]);

    await tester.pumpWidget(
      _buildSubject(
        backend,
        cloudAuthController: _WarmupRequiredCloudAuthController(),
        subscriptionController:
            _FakeSubscriptionStatusController(SubscriptionStatus.unknown),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isTrue);
    expect(find.byType(AiAskAiSettingsPage), findsNothing);
  });

  testWidgets(
      'TodoDetailPage manual regenerate allows cloud when subscription is unknown',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    _setLargeDisplay(tester);
    final backend = _Backend(llmProfiles: const <LlmProfile>[]);

    await tester.pumpWidget(
      _buildSubject(
        backend,
        cloudAuthController: _FakeCloudAuthController(),
        subscriptionController:
            _FakeSubscriptionStatusController(SubscriptionStatus.unknown),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isTrue);
    expect(find.byType(AiAskAiSettingsPage), findsNothing);
  });
}

void _setLargeDisplay(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _buildSubject(
  AppBackend backend, {
  SyncEngine? syncEngine,
  CloudAuthController? cloudAuthController,
  SubscriptionStatusController? subscriptionController,
}) {
  Widget child = AppBackendScope(
    backend: backend,
    child: SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: SyncEngineScope(
        engine: syncEngine,
        child: const TodoDetailPage(
          initialTodo: Todo(
            id: 't1',
            title: '调研一下当前主流的 llm 模型',
            status: 'open',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ),
      ),
    ),
  );

  if (cloudAuthController != null) {
    child = CloudAuthScope(
      controller: cloudAuthController,
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://example.com',
        modelName: 'cloud',
      ),
      child: child,
    );
  }
  if (subscriptionController != null) {
    child = SubscriptionScope(
      controller: subscriptionController,
      child: child,
    );
  }

  return wrapWithI18n(MaterialApp(home: child));
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get email => 'demo@example.com';

  @override
  bool? get emailVerified => true;

  @override
  String? get uid => 'uid_1';

  @override
  Future<String?> getIdToken() async => 'token_1';

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

final class _WarmupRequiredCloudAuthController implements CloudAuthController {
  var _reads = 0;

  @override
  String? get email => 'demo@example.com';

  @override
  bool? get emailVerified => true;

  @override
  String? get uid => 'uid_1';

  @override
  Future<String?> getIdToken() async {
    _reads += 1;
    return _reads >= 2 ? 'token_2' : null;
  }

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

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _Backend extends AppBackend {
  _Backend({
    List<TodoFollowupSuggestion>? initialSuggestions,
    List<TodoActivity>? initialActivities,
    List<LlmProfile>? llmProfiles,
    this.regenerateCompleter,
    this.activeGenerationJob,
  })  : _suggestions = List<TodoFollowupSuggestion>.from(
          initialSuggestions ??
              const <TodoFollowupSuggestion>[
                TodoFollowupSuggestion(
                  id: 'f1',
                  todoId: 't1',
                  content: '以下内容基于模型知识整理，未联网核实。',
                  state: 'pending',
                  source: 'cloud',
                  generationMode: 'model_knowledge',
                  generationKey: 'gen_1',
                  citationsJson: null,
                  createdAtMs: 1,
                  updatedAtMs: 1,
                  dismissedAtMs: null,
                  appliedActivityId: null,
                ),
              ],
        ),
        _activities = List<TodoActivity>.from(
            initialActivities ?? const <TodoActivity>[]),
        _llmProfiles = List<LlmProfile>.from(
          llmProfiles ??
              const <LlmProfile>[
                LlmProfile(
                  id: 'llm_1',
                  name: 'Test profile',
                  providerType: 'openai_compatible',
                  baseUrl: 'https://example.com',
                  modelName: 'gpt-test',
                  isActive: true,
                  createdAtMs: 1,
                  updatedAtMs: 1,
                ),
              ],
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final List<TodoFollowupSuggestion> _suggestions;
  final List<TodoActivity> _activities;
  final List<LlmProfile> _llmProfiles;
  final Completer<void>? regenerateCompleter;
  final TodoFollowupGenerationJob? activeGenerationJob;
  List<String> appliedSuggestionIds = <String>[];
  List<String> dismissedSuggestionIds = <String>[];
  bool enqueuedRegenerate = false;
  int getTodoFollowupGenerationJobCalls = 0;

  @override
  bool get supportsTodoFollowupSuggestions => true;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      List<LlmProfile>.from(_llmProfiles);

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      List<TodoActivity>.from(_activities);

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoChecklistItem>[];

  @override
  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoChecklistSuggestion>[];

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    Uint8List key,
    String todoId,
  ) async =>
      List<TodoFollowupSuggestion>.from(_suggestions);

  @override
  Future<List<TodoActivity>> applyTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    appliedSuggestionIds = List<String>.from(suggestionIds);
    for (var index = 0; index < _suggestions.length; index++) {
      final suggestion = _suggestions[index];
      if (!suggestionIds.contains(suggestion.id)) continue;
      _suggestions[index] = TodoFollowupSuggestion(
        id: suggestion.id,
        todoId: suggestion.todoId,
        content: suggestion.content,
        state: 'applied',
        source: suggestion.source,
        generationMode: suggestion.generationMode,
        generationKey: suggestion.generationKey,
        citationsJson: suggestion.citationsJson,
        createdAtMs: suggestion.createdAtMs,
        updatedAtMs: suggestion.updatedAtMs,
        dismissedAtMs: suggestion.dismissedAtMs,
        appliedActivityId: 'a_applied',
      );
    }
    _activities.add(
      const TodoActivity(
        id: 'a_applied',
        todoId: 't1',
        activityType: 'followup_information',
        fromStatus: null,
        toStatus: null,
        content: '以下内容基于模型知识整理，未联网核实。',
        sourceMessageId: null,
        createdAtMs: 1,
      ),
    );
    return List<TodoActivity>.from(_activities);
  }

  @override
  Future<void> dismissTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    dismissedSuggestionIds = List<String>.from(suggestionIds);
    _suggestions.removeWhere((item) => suggestionIds.contains(item.id));
  }

  @override
  Future<TodoFollowupGenerationJob?> getTodoFollowupGenerationJob(
    Uint8List key,
    String todoId,
  ) async {
    getTodoFollowupGenerationJobCalls += 1;
    return activeGenerationJob;
  }

  @override
  Future<void> enqueueTodoFollowupGenerationJob(
    Uint8List key, {
    required String todoId,
    required String triggerKind,
    String? taskTypeHint,
    required int nowMs,
  }) async {
    enqueuedRegenerate = true;
    final completer = regenerateCompleter;
    if (completer != null) {
      await completer.future;
    }
    if (_suggestions.isEmpty) {
      _suggestions.add(
        const TodoFollowupSuggestion(
          id: 'generated_f1',
          todoId: 't1',
          content: '以下内容基于模型知识整理，未联网核实。',
          state: 'pending',
          source: 'cloud',
          generationMode: 'model_knowledge',
          generationKey: 'regen_1',
          citationsJson: null,
          createdAtMs: 1,
          updatedAtMs: 1,
          dismissedAtMs: null,
          appliedActivityId: null,
        ),
      );
    }
  }
}

final class _ThrowingLlmProfilesBackend extends _Backend {
  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    throw StateError('boom');
  }
}

final class _UnsupportedBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoChecklistItem>[];

  @override
  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoChecklistSuggestion>[];
}
