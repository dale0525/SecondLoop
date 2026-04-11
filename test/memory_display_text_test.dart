import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/memory/memory_display_text.dart';
import 'package:secondloop/i18n/strings.g.dart';

void main() {
  test('localizes known generated memory titles in zh_CN', () {
    final t = AppLocale.zhCn.build();

    expect(
      resolveMemoryDisplayTitle(
        t,
        documentId: 'generated:pattern:active-task-focus',
        explicitTitle: 'Active task pattern',
      ),
      '当前任务模式',
    );
    expect(
      resolveMemoryDisplayTitle(
        t,
        documentId: 'generated:preference:response-language',
        explicitTitle: 'Response language',
      ),
      '回复语言',
    );
  });

  test('preserves custom titles for generated memories', () {
    final t = AppLocale.zhCn.build();

    expect(
      resolveMemoryDisplayTitle(
        t,
        documentId: 'generated:pattern:active-task-focus',
        explicitTitle: '我的自定义标题',
      ),
      '我的自定义标题',
    );
  });
}
