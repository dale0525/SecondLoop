import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/i18n/strings.g.dart';

void main() {
  test('task hub zh-CN labels are fully localized', () {
    final taskHub = AppLocale.zhCn.translations.actions.taskHub;

    expect(taskHub.focusSection, '重点');
    expect(taskHub.decideSection, '待决定');
    expect(taskHub.doneSection, '已完成');
    expect(taskHub.actions.doNow, '立即处理');
    expect(taskHub.actions.schedule, '安排时间');
    expect(taskHub.actions.defer, '延后');
    expect(taskHub.actions.clarify, '补充信息');
  });
}
