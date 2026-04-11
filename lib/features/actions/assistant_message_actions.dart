import 'suggestions_parser.dart';

class AssistantMessageActions {
  const AssistantMessageActions({
    required this.displayText,
    required this.suggestions,
  });

  final String displayText;
  final ParsedSuggestions? suggestions;
}

final RegExp _kDisplayOnlyCitationUuidPattern = RegExp(
  r'\s*\[[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\]',
);

AssistantMessageActions parseAssistantMessageActions(String rawText) {
  final suggestions = SuggestionsParser.tryParse(rawText);
  final displayText = _stripDisplayOnlyCitationIds(
    SuggestionsParser.stripActionsBlock(rawText),
  );
  return AssistantMessageActions(
      displayText: displayText, suggestions: suggestions);
}

String _stripDisplayOnlyCitationIds(String text) {
  final stripped = text.replaceAll(_kDisplayOnlyCitationUuidPattern, '');
  final compactSpaces = stripped.replaceAll(RegExp(r' {2,}'), ' ');
  final betweenCjk = compactSpaces.replaceAllMapped(
    RegExp(r'([\u4E00-\u9FFF])\s+([\u4E00-\u9FFF])'),
    (match) => '${match.group(1)}${match.group(2)}',
  );
  return betweenCjk.replaceAllMapped(
    RegExp(r'([\u4E00-\u9FFF])\s+([，。！？；：、])'),
    (match) => '${match.group(1)}${match.group(2)}',
  );
}
