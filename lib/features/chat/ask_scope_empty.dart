class AskScopeEmptyResponse {
  const AskScopeEmptyResponse._();

  static const String zhHans =
      '在当前范围内未找到结果（时间窗口 + 标签 + 范围）。\n你可以尝试：\n1. 扩大时间窗口\n2. 移除包含标签\n3. 切换范围到 All';

  static const String english =
      'No results found in the current scope (time window + tags + focus).\nYou can try:\n1. Expand the time window\n2. Remove include tags\n3. Switch scope to All';

  static bool matches(String raw) {
    final normalized = _normalize(raw);
    return normalized == _normalize(zhHans) ||
        normalized == _normalize(english);
  }

  static String summaryLine(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return lines.isEmpty ? raw.trim() : lines.first;
  }

  static String _normalize(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }
}

enum AskScopeEmptyAction {
  expandTimeWindow,
  removeIncludeTags,
  switchScopeToAll,
}
