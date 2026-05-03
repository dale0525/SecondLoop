import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/local_todo_command_parser.dart';
import 'package:secondloop/core/secretary/todo_command_models.dart';
import 'package:secondloop/features/actions/todo/todo_linking.dart';

void main() {
  group('LocalTodoCommandParser', () {
    final now = DateTime(2026, 5, 4, 9);

    test('parses zh reschedule command with clear target', () {
      final result = LocalTodoCommandParser.parse(
        messageId: 'm1',
        text: '把报销改到明天下午',
        nowLocal: now,
        locale: const Locale('zh', 'CN'),
        openTodoTargets: const [
          TodoLinkTarget(id: 'todo-1', title: '报销', status: 'open'),
        ],
      );

      expect(result.command?.kind, SecretaryTodoCommandKind.reschedule);
      expect(result.command?.targetTodoId, 'todo-1');
      expect(result.command?.dueAtMs, isNotNull);
      expect(result.needsEnhancement, isFalse);
    });

    test('parses zh rename command with clear target', () {
      final result = LocalTodoCommandParser.parse(
        messageId: 'm2',
        text: '把报销改成提交差旅报销',
        nowLocal: now,
        locale: const Locale('zh', 'CN'),
        openTodoTargets: const [
          TodoLinkTarget(id: 'todo-1', title: '报销', status: 'open'),
        ],
      );

      expect(result.command?.kind, SecretaryTodoCommandKind.updateTitle);
      expect(result.command?.targetTodoId, 'todo-1');
      expect(result.command?.newTitle, '提交差旅报销');
    });

    test('parses delete as dismiss command requiring later confirmation', () {
      final result = LocalTodoCommandParser.parse(
        messageId: 'm3',
        text: '删除报销',
        nowLocal: now,
        locale: const Locale('zh', 'CN'),
        openTodoTargets: const [
          TodoLinkTarget(id: 'todo-1', title: '报销', status: 'open'),
        ],
      );

      expect(result.command?.kind, SecretaryTodoCommandKind.dismiss);
      expect(result.command?.targetTodoId, 'todo-1');
    });

    test('parses priority increase command', () {
      final result = LocalTodoCommandParser.parse(
        messageId: 'm4',
        text: '把报销优先级调高',
        nowLocal: now,
        locale: const Locale('zh', 'CN'),
        openTodoTargets: const [
          TodoLinkTarget(id: 'todo-1', title: '报销', status: 'open'),
        ],
      );

      expect(result.command?.kind, SecretaryTodoCommandKind.reprioritize);
      expect(result.command?.manualImportanceNudgeScore, 1);
      expect(result.command?.manualUrgencyNudgeScore, 1);
    });

    test('parses english rename and priority commands', () {
      final rename = LocalTodoCommandParser.parse(
        messageId: 'm5',
        text: 'Rename invoice to Submit Stripe invoice',
        nowLocal: now,
        locale: const Locale('en'),
        openTodoTargets: const [
          TodoLinkTarget(id: 'todo-1', title: 'invoice', status: 'open'),
        ],
      );
      final priority = LocalTodoCommandParser.parse(
        messageId: 'm6',
        text: 'Make invoice more important',
        nowLocal: now,
        locale: const Locale('en'),
        openTodoTargets: const [
          TodoLinkTarget(id: 'todo-1', title: 'invoice', status: 'open'),
        ],
      );

      expect(rename.command?.kind, SecretaryTodoCommandKind.updateTitle);
      expect(rename.command?.newTitle, 'Submit Stripe invoice');
      expect(priority.command?.kind, SecretaryTodoCommandKind.reprioritize);
      expect(priority.command?.manualImportanceNudgeScore, 1);
    });

    test('ambiguous targets return no command and request enhancement', () {
      final result = LocalTodoCommandParser.parse(
        messageId: 'm7',
        text: '把报销改成提交差旅报销',
        nowLocal: now,
        locale: const Locale('zh', 'CN'),
        openTodoTargets: const [
          TodoLinkTarget(id: 'todo-1', title: '报销', status: 'open'),
          TodoLinkTarget(id: 'todo-2', title: '报销', status: 'open'),
        ],
      );

      expect(result.command, isNull);
      expect(result.isAmbiguous, isTrue);
      expect(result.needsEnhancement, isTrue);
      expect(result.diagnostic, 'ambiguous_todo_command');
    });
  });
}
