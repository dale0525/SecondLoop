import 'dart:convert';

class ActionSuggestion {
  const ActionSuggestion({
    required this.type,
    required this.title,
    this.whenText,
  });

  final String type; // "todo" | "event"
  final String title;
  final String? whenText;
}

class ParsedSuggestions {
  const ParsedSuggestions({
    required this.version,
    required this.suggestions,
  });

  final int version;
  final List<ActionSuggestion> suggestions;
}

class SuggestionsParser {
  static const _fence = '```';
  static const _tag = 'secondloop_actions';

  static ParsedSuggestions? tryParse(String text) {
    final start = text.indexOf('$_fence$_tag');
    if (start < 0) return null;

    final bodyStart = text.indexOf('\n', start);
    if (bodyStart < 0) return null;

    final end = text.indexOf(_fence, bodyStart + 1);
    if (end < 0) return null;

    final jsonText = text.substring(bodyStart + 1, end).trim();
    if (jsonText.isEmpty) return null;

    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;

    final version = decoded['version'];
    final suggestionsRaw = decoded['suggestions'];
    if (version is! int || suggestionsRaw is! List) return null;

    final suggestions = <ActionSuggestion>[];
    for (final item in suggestionsRaw) {
      if (item is! Map) continue;
      final type = item['type'];
      final title = item['title'];
      final whenText = item['when'];
      if (type is! String || title is! String) continue;
      suggestions.add(
        ActionSuggestion(
          type: type,
          title: title,
          whenText: whenText is String ? whenText : null,
        ),
      );
    }

    return ParsedSuggestions(version: version, suggestions: suggestions);
  }

  static String stripActionsBlock(String text) {
    final start = text.indexOf('$_fence$_tag');
    if (start < 0) return text;

    final bodyStart = text.indexOf('\n', start);
    if (bodyStart < 0) return text;

    final end = text.indexOf(_fence, bodyStart + 1);
    if (end < 0) {
      return text.substring(0, start).trimRight();
    }

    final after = end + _fence.length;
    final before = text.substring(0, start).trimRight();
    final rest = text.substring(after).trimLeft();

    if (before.isEmpty) return rest;
    if (rest.isEmpty) return before;
    return '$before\n\n$rest';
  }
}
