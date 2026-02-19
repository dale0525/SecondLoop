import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/ask_scope_empty.dart';

void main() {
  test('matches strict scoped empty answer in zh and en', () {
    const zh =
        '在当前范围内未找到结果（时间窗口 + 标签 + 范围）。\n你可以尝试：\n1. 扩大时间窗口\n2. 移除包含标签\n3. 切换范围到 All';
    const en =
        'No results found in the current scope (time window + tags + focus).\nYou can try:\n1. Expand the time window\n2. Remove include tags\n3. Switch scope to All';

    expect(AskScopeEmptyResponse.matches(zh), isTrue);
    expect(AskScopeEmptyResponse.matches(en), isTrue);
  });

  test('does not match normal assistant answer', () {
    expect(AskScopeEmptyResponse.matches('This is a normal answer.'), isFalse);
  });
}
