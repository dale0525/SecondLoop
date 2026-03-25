import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/i18n/strings.g.dart';

void main() {
  test('task hub zh-CN labels are fully localized', () {
    final taskHub = AppLocale.zhCn.translations.actions.taskHub;

    expect(taskHub.focusSection, '当前重点');
    expect(taskHub.scheduledSection, '下一步');
    expect(taskHub.unscheduledSection, '积压');
    expect(taskHub.currentFocus, '当前重点');
    expect(taskHub.doneSection, '已完成');
    expect(
      AppLocale.zhCn.translations.actions.agenda.undeterminedSummary(count: 3),
      '积压 3 条',
    );
    expect(
      AppLocale.zhCn.translations.actions.agenda.upcomingSummary(count: 2),
      '下一步 2 条',
    );
    expect(taskHub.actions.doNow, '立即处理');
    expect(taskHub.actions.schedule, '安排时间');
    expect(taskHub.actions.defer, '延后');
    expect(taskHub.actions.clarify, '补充信息');
  });
}
