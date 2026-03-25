import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/features/settings/ai_ask_ai_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('TodoDetailPage applies selected suggestions', (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('todo_detail_checklist_suggestion_select_s1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_apply_selected')),
    );
    await tester.pumpAndSettle();

    expect(backend.appliedSuggestionIds, const <String>['s1']);
  });

  testWidgets('TodoDetailPage dismisses selected suggestions', (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('todo_detail_checklist_suggestion_select_s1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_dismiss_selected')),
    );
    await tester.pumpAndSettle();

    expect(backend.dismissedSuggestionIds, const <String>['s1']);
  });

  testWidgets('TodoDetailPage applies all suggestions', (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_apply_all')),
    );
    await tester.pumpAndSettle();

    expect(backend.appliedSuggestionIds, const <String>['s1', 's2']);
  });

  testWidgets('TodoDetailPage shows generating state while suggestions load',
      (tester) async {
    _setLargeDisplay(tester);
    final completer = Completer<String>();
    final backend = _Backend(
      initialSuggestions: const <TodoChecklistSuggestion>[],
      generationResponseCompleter: completer,
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_generate_suggestions')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('todo_detail_checklist_generating_indicator')),
      findsOneWidget,
    );
    expect(find.text('Generating suggestions…'), findsOneWidget);

    completer
        .complete('{"suggestions":["Draft launch post","Share with team"]}');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_checklist_generating_indicator')),
      findsNothing,
    );
    expect(backend.generatedSuggestionContents, const <String>[
      'Draft launch post',
      'Share with team',
    ]);
  });

  testWidgets('TodoDetailPage generation continues after leaving page',
      (tester) async {
    _setLargeDisplay(tester);
    final completer = Completer<String>();
    final backend = _Backend(
      initialSuggestions: const <TodoChecklistSuggestion>[],
      generationResponseCompleter: completer,
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_generate_suggestions')),
    );
    await tester.pump();

    await tester.pumpWidget(
      wrapWithI18n(const MaterialApp(home: Scaffold(body: SizedBox.shrink()))),
    );
    await tester.pump();

    completer.complete('{"suggestions":["Draft launch post"]}');
    await tester.pumpAndSettle();

    expect(backend.generatedSuggestionContents, const <String>[
      'Draft launch post',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'TodoDetailPage renders many suggestions without nested checklist scroll',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend(
      initialSuggestions: List<TodoChecklistSuggestion>.generate(
        8,
        (index) => TodoChecklistSuggestion(
          id: 's$index',
          todoId: 't1',
          content: 'Suggested step $index',
          sortOrder: index,
          state: 'pending',
          source: 'cloud',
          generationKey: 'gen_many',
          createdAtMs: 1,
          updatedAtMs: 1,
          dismissedAtMs: null,
          appliedChecklistItemId: null,
        ),
      ),
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_checklist_content_scroll')),
      findsNothing,
    );
    expect(find.text('Suggested step 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TodoDetailPage generates suggestions via BYOK', (tester) async {
    _setLargeDisplay(tester);
    final backend =
        _Backend(initialSuggestions: const <TodoChecklistSuggestion>[]);

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_generate_suggestions')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(backend.generatedSuggestionContents, const <String>[
      'Draft launch post',
      'Share with team',
    ]);
    expect(find.text('Share with team'), findsOneWidget);
  });

  testWidgets('TodoDetailPage generates checklist suggestions via cloud route',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend(
      initialSuggestions: const <TodoChecklistSuggestion>[],
      llmProfiles: const <LlmProfile>[],
    );

    await tester.pumpWidget(
      _buildSubject(
        backend,
        cloudAuthController: const _FakeCloudAuthController('token_1'),
        subscriptionController:
            _FakeSubscriptionStatusController(SubscriptionStatus.unknown),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_generate_suggestions')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(backend.generatedSuggestionContents, const <String>[
      'Cloud launch checklist',
      'Share with team',
    ]);
    expect(backend.lastGeneratedSource, 'cloud');
    expect(find.text('Cloud launch checklist'), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage opens Ask AI settings when generation needs setup',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend(
      initialSuggestions: const <TodoChecklistSuggestion>[],
      llmProfiles: const <LlmProfile>[],
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiAskAiSettingsPage), findsOneWidget);
  });

  testWidgets('TodoDetailPage shows snackbar when applying suggestions fails',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend(applyError: StateError('apply failed'));

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_apply_all')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('apply failed'), findsOneWidget);
  });

  testWidgets('TodoDetailPage shows snackbar when dismissing suggestions fails',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend(dismissError: StateError('dismiss failed'));

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_suggestion_select_s1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_dismiss_selected')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('dismiss failed'), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage shows snackbar when dismissing all suggestions fails',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend(
      dismissAllError: StateError('dismiss all failed'),
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_dismiss_all')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('dismiss all failed'), findsOneWidget);
  });
}

void _setLargeDisplay(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _buildSubject(
  _Backend backend, {
  CloudAuthController? cloudAuthController,
  SubscriptionStatusController? subscriptionController,
}) {
  Widget child = AppBackendScope(
    backend: backend,
    child: SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: const TodoDetailPage(
        initialTodo: Todo(
          id: 't1',
          title: 'Task',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
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

final class _Backend extends AppBackend {
  _Backend({
    List<TodoChecklistSuggestion>? initialSuggestions,
    List<LlmProfile>? llmProfiles,
    this.generationResponseCompleter,
    this.applyError,
    this.dismissError,
    this.dismissAllError,
  })  : _suggestions = List<TodoChecklistSuggestion>.from(
          initialSuggestions ??
              const <TodoChecklistSuggestion>[
                TodoChecklistSuggestion(
                  id: 's1',
                  todoId: 't1',
                  content: 'Draft launch post',
                  sortOrder: 0,
                  state: 'pending',
                  source: 'cloud',
                  generationKey: 'gen_1',
                  createdAtMs: 1,
                  updatedAtMs: 1,
                  dismissedAtMs: null,
                  appliedChecklistItemId: null,
                ),
                TodoChecklistSuggestion(
                  id: 's2',
                  todoId: 't1',
                  content: 'Share with team',
                  sortOrder: 1,
                  state: 'pending',
                  source: 'cloud',
                  generationKey: 'gen_1',
                  createdAtMs: 1,
                  updatedAtMs: 1,
                  dismissedAtMs: null,
                  appliedChecklistItemId: null,
                ),
              ],
        ),
        _llmProfiles = List<LlmProfile>.from(
          llmProfiles ??
              const <LlmProfile>[
                LlmProfile(
                  id: 'p1',
                  name: 'Test Profile',
                  providerType: 'openai-compatible',
                  baseUrl: 'https://example.com/v1',
                  modelName: 'gpt-4o-mini',
                  isActive: true,
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ],
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  List<String> appliedSuggestionIds = <String>[];
  List<String> dismissedSuggestionIds = <String>[];
  List<String> generatedSuggestionContents = <String>[];
  String? lastGeneratedSource;
  final Completer<String>? generationResponseCompleter;
  final Object? applyError;
  final Object? dismissError;
  final Object? dismissAllError;
  final List<TodoChecklistSuggestion> _suggestions;
  final List<LlmProfile> _llmProfiles;

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
  Future<List<TodoActivity>> listTodoActivities(
          Uint8List key, String todoId) async =>
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
      List<TodoChecklistSuggestion>.from(_suggestions);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      List<LlmProfile>.from(_llmProfiles);

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    final completer = generationResponseCompleter;
    if (completer != null) {
      return completer.future;
    }
    return '{"suggestions":["Draft launch post","Share with team"]}';
  }

  @override
  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    return '{"suggestions":["Cloud launch checklist","Share with team"]}';
  }

  @override
  Future<List<TodoChecklistSuggestion>> upsertGeneratedTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) async {
    generatedSuggestionContents = List<String>.from(suggestions);
    lastGeneratedSource = source;
    _suggestions
      ..clear()
      ..addAll(
        List<TodoChecklistSuggestion>.generate(
          suggestions.length,
          (index) => TodoChecklistSuggestion(
            id: 'generated_$index',
            todoId: todoId,
            content: suggestions[index],
            sortOrder: index,
            state: 'pending',
            source: source,
            generationKey: generationKey,
            createdAtMs: 1,
            updatedAtMs: 1,
            dismissedAtMs: null,
            appliedChecklistItemId: null,
          ),
        ),
      );
    return List<TodoChecklistSuggestion>.from(_suggestions);
  }

  @override
  Future<List<TodoChecklistItem>> applyTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    if (applyError != null) throw applyError!;
    appliedSuggestionIds = List<String>.from(suggestionIds);
    return const <TodoChecklistItem>[];
  }

  @override
  Future<void> dismissTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    if (dismissError != null) throw dismissError!;
    dismissedSuggestionIds = List<String>.from(suggestionIds);
    _suggestions.removeWhere((item) => suggestionIds.contains(item.id));
  }

  @override
  Future<void> dismissAllTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
  }) async {
    if (dismissAllError != null) throw dismissAllError!;
    dismissedSuggestionIds =
        _suggestions.map((item) => item.id).toList(growable: false);
    _suggestions.clear();
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  const _FakeCloudAuthController(this._token);

  final String _token;

  @override
  String? get email => 'demo@example.com';

  @override
  bool? get emailVerified => true;

  @override
  String? get uid => 'uid_1';

  @override
  Future<String?> getIdToken() async => _token;

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
