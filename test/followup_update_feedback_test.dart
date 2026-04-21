import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/followup_update_feedback.dart';

void main() {
  test('builds due-only followup feedback without status wording', () {
    final text = buildFollowupUpdateFeedbackText(
      title: '报销',
      didUpdateStatus: false,
      didUpdateDue: true,
      statusLabel: '进行中',
      updatedStatusBuilder: ({required String title, required String status}) =>
          '已更新「$title」为：$status',
      updatedDueBuilder: ({required String title}) => '已更新「$title」的时间',
      updatedStatusAndDueBuilder: ({required String title}) =>
          '已更新「$title」的状态和时间',
    );

    expect(text, '已更新「报销」的时间');
  });

  test('builds combined followup feedback when both status and due change', () {
    final text = buildFollowupUpdateFeedbackText(
      title: '报销',
      didUpdateStatus: true,
      didUpdateDue: true,
      statusLabel: '进行中',
      updatedStatusBuilder: ({required String title, required String status}) =>
          '已更新「$title」为：$status',
      updatedDueBuilder: ({required String title}) => '已更新「$title」的时间',
      updatedStatusAndDueBuilder: ({required String title}) =>
          '已更新「$title」的状态和时间',
    );

    expect(text, '已更新「报销」的状态和时间');
  });
}
