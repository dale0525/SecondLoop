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

  test('localizes known generated memory summaries in zh_CN', () {
    final t = AppLocale.zhCn.build();

    expect(
      resolveMemoryDisplaySummary(
        t,
        documentId: 'generated:preference:response-language',
        explicitSummary: 'User prefers responses in Chinese.',
        rawText: 'User prefers responses in Chinese.',
      ),
      '用户偏好使用中文回复。',
    );
    expect(
      resolveMemoryDisplaySummary(
        t,
        documentId: 'generated:preference:response-style',
        explicitSummary: 'User prefers concise, practical responses.',
        rawText: 'User prefers concise, practical responses.',
      ),
      '用户偏好简洁、务实的回复风格。',
    );
    expect(
      resolveMemoryDisplaySummary(
        t,
        documentId: 'generated:pattern:active-task-focus',
        explicitSummary: 'User is actively working across these task threads:',
        rawText:
            'User is actively working across these task threads:\n- 做视频 [in_progress]\n- 复盘选题 [open]',
      ),
      '用户当前主要在推进这些任务：',
    );
  });

  test('localizes generated pattern body and internal section labels', () {
    final t = AppLocale.zhCn.build();

    expect(
      resolveMemoryDisplayBody(
        t,
        documentId: 'generated:pattern:active-task-focus',
        rawText:
            'User is actively working across these task threads:\n- 做视频 [in_progress]\n- 复盘选题 [open]',
      ),
      '用户当前主要在推进这些任务：\n- 做视频 [进行中]\n- 复盘选题 [未开始]',
    );
    expect(
      resolveMemorySectionLabel(t, rawSectionLabel: 'generated_pattern'),
      '摘要来源',
    );
  });
}
