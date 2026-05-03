import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/secretary/todo_command_models.dart';
import 'package:secondloop/features/secretary/todo_command_review_card.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('updateTitle review card shows current and proposed title',
      (tester) async {
    var applied = false;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ChatSecretaryTodoCommandCard(
              command: _renameCommand(),
              onApply: () => applied = true,
              onReview: () {},
              onIgnore: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Todo change needs review'), findsOneWidget);
    expect(find.text('Rename Submit invoice -> Submit Stripe invoice'),
        findsOneWidget);
    expect(find.text('Submit invoice'), findsWidgets);
    expect(find.text('Submit Stripe invoice'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('secretary_todo_command_apply_cmd-rename')),
    );
    expect(applied, isTrue);
  });

  testWidgets('dismiss card requires explicit confirm', (tester) async {
    var reviewed = false;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ChatSecretaryTodoCommandCard(
              command: _deleteCommand(),
              onApply: () => fail('delete must not apply from chat card'),
              onReview: () => reviewed = true,
              onIgnore: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Delete Submit invoice'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('secretary_todo_command_apply_cmd-delete')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('secretary_todo_command_review_cmd-delete')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('secretary_todo_command_review_cmd-delete')),
    );
    expect(reviewed, isTrue);
  });

  testWidgets('rejected command does not show an apply button', (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ChatSecretaryTodoCommandCard(
              command: _invalidCommand(),
              onApply: () => fail('invalid command must not be applied'),
              onReview: () {},
              onIgnore: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Todo change needs review'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('secretary_todo_command_apply_cmd-invalid')),
      findsNothing,
    );
  });

  testWidgets('ignoring card does not call apply', (tester) async {
    var applied = false;
    var ignored = false;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ChatSecretaryTodoCommandCard(
              command: _renameCommand(),
              onApply: () => applied = true,
              onReview: () {},
              onIgnore: () => ignored = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('secretary_todo_command_ignore_cmd-rename')),
    );

    expect(ignored, isTrue);
    expect(applied, isFalse);
  });
}

SecretaryTodoCommand _renameCommand() {
  return const SecretaryTodoCommand(
    id: 'cmd-rename',
    kind: SecretaryTodoCommandKind.updateTitle,
    route: SecretaryTodoCommandRoute.local,
    confidence: 0.93,
    sourceMessageId: 'm1',
    targetTodoId: 'todo:invoice',
    targetTitle: 'Submit invoice',
    newTitle: 'Submit Stripe invoice',
  );
}

SecretaryTodoCommand _deleteCommand() {
  return const SecretaryTodoCommand(
    id: 'cmd-delete',
    kind: SecretaryTodoCommandKind.dismiss,
    route: SecretaryTodoCommandRoute.local,
    confidence: 0.93,
    sourceMessageId: 'm2',
    targetTodoId: 'todo:invoice',
    targetTitle: 'Submit invoice',
  );
}

SecretaryTodoCommand _invalidCommand() {
  return const SecretaryTodoCommand(
    id: 'cmd-invalid',
    kind: SecretaryTodoCommandKind.updateTitle,
    route: SecretaryTodoCommandRoute.local,
    confidence: 0.3,
    sourceMessageId: 'm3',
    targetTodoId: 'todo:invoice',
    targetTitle: 'Submit invoice',
  );
}
