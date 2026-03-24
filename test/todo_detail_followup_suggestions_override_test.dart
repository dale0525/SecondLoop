import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/src/rust/db.dart';

import 'todo_detail_followup_suggestions_test_shared.dart';

void main() {
  testWidgets('TodoDetailPage shows override entry for execution tasks',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'manual_regenerate',
        status: 'failed',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        taskTypeHint: 'execution',
        manualOverrideFollowup: false,
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
        findsNothing);
    expect(
        find.byKey(
            const ValueKey('todo_detail_followup_force_generate_suggestions')),
        findsOneWidget);
    expect(
      find.text(
          AppLocale.zhCn.build().actions.todoDetail.followupForceGenerate),
      findsOneWidget,
    );
    expect(
      find.text(
        AppLocale.zhCn.build().actions.todoDetail.followupForceGenerateHint,
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
          const ValueKey('todo_detail_followup_force_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isTrue);
    expect(backend.lastManualOverrideFollowup, isTrue);
  });
}
