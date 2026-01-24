import 'suggestions_parser.dart';

class AssistantMessageActions {
  const AssistantMessageActions({
    required this.displayText,
    required this.suggestions,
  });

  final String displayText;
  final ParsedSuggestions? suggestions;
}

AssistantMessageActions parseAssistantMessageActions(String rawText) {
  final suggestions = SuggestionsParser.tryParse(rawText);
  final displayText = SuggestionsParser.stripActionsBlock(rawText);
  return AssistantMessageActions(
      displayText: displayText, suggestions: suggestions);
}
