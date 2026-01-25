import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/actions/todo/todo_linking.dart';

void main() {
  test('ranks todo by keyword overlap and time proximity', () {
    final now = DateTime(2026, 1, 25, 13, 50);
    final todos = [
      TodoLinkTarget(
        id: 't1',
        title: '下午 2 点有客户来拜访，需要接待',
        status: 'open',
        dueLocal: DateTime(2026, 1, 25, 14, 0),
      ),
      const TodoLinkTarget(
        id: 't2',
        title: '周末给狗狗做口粮',
        status: 'open',
      ),
    ];

    final ranked = rankTodoCandidates('接到了客户', todos, nowLocal: now);
    expect(ranked.first.target.id, 't1');
  });

  test('infers done intent for completion phrases', () {
    expect(inferTodoUpdateIntent('狗粮做完了').newStatus, 'done');
  });

  test('infers in_progress intent for progress updates', () {
    expect(inferTodoUpdateIntent('接到了客户').newStatus, 'in_progress');
  });
}
