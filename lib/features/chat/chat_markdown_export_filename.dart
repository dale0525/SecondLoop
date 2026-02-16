const _kDefaultExportFilename = 'markdown-export';
const _kDefaultExportStemMaxLength = 64;

String deriveMarkdownExportFilenameStem(
  String markdown, {
  int maxLength = _kDefaultExportStemMaxLength,
}) {
  final heading = _extractFirstHeading(markdown);
  final firstSentence = _extractFirstSentence(markdown);
  final raw = heading.isNotEmpty ? heading : firstSentence;

  final sanitized = _sanitizeFilenameStem(
    raw,
    maxLength: maxLength,
  );
  if (sanitized.isEmpty) {
    return _kDefaultExportFilename;
  }
  return sanitized;
}

String _extractFirstHeading(String markdown) {
  final headingMatch = RegExp(
    r'^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$',
    multiLine: true,
  ).firstMatch(markdown);
  if (headingMatch == null) return '';
  final headingText = headingMatch.group(1) ?? '';
  return _stripInlineMarkdown(headingText).trim();
}

String _extractFirstSentence(String markdown) {
  final normalized = markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
  if (normalized.isEmpty) return '';

  final compact = normalized
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compact.isEmpty) return '';

  final sentenceMatch = RegExp(r'^(.+?[。！？.!?])(?:\s|$)').firstMatch(compact);
  final sentence = sentenceMatch?.group(1) ?? compact;
  return _stripInlineMarkdown(sentence).trim();
}

String _stripInlineMarkdown(String input) {
  var text = input;
  text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1');
  text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1');
  text = text.replaceAll(RegExp(r'`([^`]*)`'), r'$1');
  text = text.replaceAll(RegExp(r'[*_~]+'), '');
  return text;
}

String _sanitizeFilenameStem(
  String input, {
  required int maxLength,
}) {
  if (maxLength <= 0) return '';

  var text = input
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'[/\\?%*:|"<>]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (text.isEmpty) return '';

  text = text.replaceAll('...', ' ').replaceAll(RegExp(r'\.{2,}'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  text = text.replaceAll(' ', '-');
  text = text.replaceAll(RegExp(r'-+'), '-');
  text = text.replaceAll(RegExp(r'^[-_.]+|[-_.]+$'), '');

  if (text.isEmpty) return '';

  if (text.runes.length > maxLength) {
    text = String.fromCharCodes(text.runes.take(maxLength));
    text = text.replaceAll(RegExp(r'^[-_.]+|[-_.]+$'), '');
  }

  return text;
}
