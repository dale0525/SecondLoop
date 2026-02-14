final RegExp _kSemanticParseBareStatusUpdateRegex = RegExp(
  r'^[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]*'
  r'(done|finished|finish|complete|completed|cancel|cancelled|dismiss|delete|deleted|'
  r'完成|完成了|已完成|做完|做完了|搞定|搞定了|取消|不用了|算了|删掉|删除|刪除|'
  r'完了|完了した|終わった|完了|中止|キャンセル|削除|'
  r'취소|삭제)'
  r'[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]*$',
  caseSensitive: false,
);

final RegExp _kSemanticParseTrimPunctuationEndsRegex = RegExp(
  r'^[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]+|[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]+$',
);

final RegExp _kSemanticParseNoiseCharsRegex = RegExp(
  r'[\s\.\,!?\u3002\uff01\uff1f\uFF0C\u3001\uFF1A\uFF1B\u2026\u2014\u2013\u2012\u2010\uFF0D\uFF5E]+',
);

bool looksLikeBareTodoStatusUpdateForSemanticParse(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == '✅' || trimmed == '✔' || trimmed == '✓') return true;
  return _kSemanticParseBareStatusUpdateRegex.hasMatch(trimmed);
}

bool looksLikeTodoRelevantForSemanticParse(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.contains('\n')) return false;
  if (trimmed.runes.length >= 200) return false;
  if (trimmed.contains('?') || trimmed.contains('？')) return false;
  if (looksLikeBareTodoStatusUpdateForSemanticParse(trimmed)) return false;

  final normalized = trimmed
      .toLowerCase()
      .replaceAll(_kSemanticParseTrimPunctuationEndsRegex, '')
      .trim();

  const ignored = <String>{
    'hi',
    'hello',
    'hey',
    'ok',
    'okay',
    'k',
    'kk',
    'thanks',
    'thank you',
    'thx',
    'lol',
    'haha',
    'yep',
    'nope',
    'yes',
    'no',
    'sure',
    'nice',
    'good',
    'great',
    'cool',
    '👍',
    '👌',
    '🙏',
    '你好',
    '嗨',
    '在吗',
    '好的',
    '好',
    '行',
    '可以',
    'ok了',
    '谢谢',
    '谢了',
    '哈哈',
    '嗯',
  };

  if (normalized.isEmpty) return false;
  if (ignored.contains(normalized)) return false;
  return true;
}

bool shouldRequeueSemanticParseAfterMessageEdit({
  required String previousText,
  required String editedText,
  required bool isSourceEntry,
}) {
  if (!isSourceEntry) return false;

  final normalizedPrevious = _normalizeForSemanticEditComparison(previousText);
  final normalizedEdited = _normalizeForSemanticEditComparison(editedText);
  if (normalizedEdited.isEmpty) return false;
  if (normalizedPrevious == normalizedEdited) return false;

  return looksLikeTodoRelevantForSemanticParse(editedText);
}

String _normalizeForSemanticEditComparison(String text) {
  return text
      .toLowerCase()
      .replaceAll(_kSemanticParseNoiseCharsRegex, '')
      .trim();
}
