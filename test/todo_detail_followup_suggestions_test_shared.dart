import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void setLargeDisplay(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget buildTodoDetailSubject(
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

final class NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class FakeCloudAuthController implements CloudAuthController {
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

final class WarmupRequiredCloudAuthController implements CloudAuthController {
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

final class FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class TestBackend extends AppBackend {
  TestBackend({
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
  bool lastManualOverrideFollowup = false;
  String? lastTaskTypeHint;
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
    bool manualOverrideFollowup = false,
    String? taskTypeHint,
    required int nowMs,
  }) async {
    enqueuedRegenerate = true;
    lastManualOverrideFollowup = manualOverrideFollowup;
    lastTaskTypeHint = taskTypeHint;
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

final class ThrowingLlmProfilesBackend extends TestBackend {
  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    throw StateError('boom');
  }
}

final class UnsupportedBackend extends AppBackend {
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
