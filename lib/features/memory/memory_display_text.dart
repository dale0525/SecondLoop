import '../../i18n/strings.g.dart';

String resolveMemoryDisplayTitle(
  Translations t, {
  required String documentId,
  String? explicitTitle,
  String? correctedTitle,
}) {
  final normalizedCorrected = correctedTitle?.trim();
  if (normalizedCorrected != null && normalizedCorrected.isNotEmpty) {
    return normalizedCorrected;
  }

  final localized = _localizedKnownGeneratedMemoryTitle(t, documentId);
  final normalizedExplicit = explicitTitle?.trim();
  if (localized != null &&
      (normalizedExplicit == null ||
          normalizedExplicit.isEmpty ||
          _matchesKnownGeneratedEnglishTitle(documentId, normalizedExplicit))) {
    return localized;
  }

  if (normalizedExplicit != null && normalizedExplicit.isNotEmpty) {
    return normalizedExplicit;
  }

  if (localized != null) {
    return localized;
  }

  return _fallbackMemoryTitleFromDocumentId(documentId);
}

String? _localizedKnownGeneratedMemoryTitle(
  Translations t,
  String documentId,
) {
  return switch (documentId.trim()) {
    'generated:pattern:active-task-focus' =>
      t.memory.generatedTitles.activeTaskPattern,
    'generated:pattern:weekly-focus' => t.memory.generatedTitles.weeklyFocus,
    'generated:preference:response-language' =>
      t.memory.generatedTitles.responseLanguage,
    'generated:preference:response-style' =>
      t.memory.generatedTitles.responseStyle,
    'generated:preference:response-format' =>
      t.memory.generatedTitles.responseFormat,
    'generated:profile:self-profile' => t.memory.generatedTitles.selfProfile,
    _ => null,
  };
}

bool _matchesKnownGeneratedEnglishTitle(String documentId, String title) {
  final normalized = title.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  final aliases = switch (documentId.trim()) {
    'generated:pattern:active-task-focus' => const <String>[
        'active task pattern',
        'active task focus',
      ],
    'generated:pattern:weekly-focus' => const <String>['weekly focus'],
    'generated:preference:response-language' => const <String>[
        'response language'
      ],
    'generated:preference:response-style' => const <String>['response style'],
    'generated:preference:response-format' => const <String>['response format'],
    'generated:profile:self-profile' => const <String>[
        'self profile',
        'profile',
      ],
    _ => const <String>[],
  };
  return aliases.contains(normalized);
}

String _fallbackMemoryTitleFromDocumentId(String documentId) {
  final trimmed = documentId.trim();
  if (trimmed.isEmpty) return trimmed;

  final segments = trimmed.split(':');
  if (segments.length >= 3) {
    return _titleCase(segments.sublist(2).join(' '));
  }
  return _titleCase(trimmed.replaceAll(':', ' '));
}

String _titleCase(String value) {
  final words = value
      .trim()
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return value.trim();
  return words
      .map(
        (word) => word.length == 1
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
