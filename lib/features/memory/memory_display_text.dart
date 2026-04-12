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

String resolveMemoryDisplaySummary(
  Translations t, {
  required String documentId,
  String? explicitSummary,
  String? rawText,
  String? correctedSummary,
}) {
  final normalizedCorrected = correctedSummary?.trim();
  if (normalizedCorrected != null && normalizedCorrected.isNotEmpty) {
    return normalizedCorrected;
  }

  final localizedBody = resolveMemoryDisplayBody(
    t,
    documentId: documentId,
    rawText: rawText ?? explicitSummary ?? '',
  ).trim();
  if (localizedBody.isNotEmpty) {
    final firstLine = localizedBody.split('\n').first.trim();
    if (firstLine.isNotEmpty) {
      return firstLine;
    }
  }

  final normalizedSummary = explicitSummary?.trim();
  if (normalizedSummary != null && normalizedSummary.isNotEmpty) {
    return normalizedSummary;
  }

  return '';
}

String resolveMemoryDisplayBody(
  Translations t, {
  required String documentId,
  required String rawText,
}) {
  final normalized = rawText.trim();
  if (normalized.isEmpty) return '';

  switch (documentId.trim()) {
    case 'generated:preference:response-language':
      final language = _extractGeneratedResponseLanguage(normalized);
      if (language == null) return normalized;
      return t.memory.generatedSummaries.responseLanguage(language: language);
    case 'generated:preference:response-style':
      return t.memory.generatedSummaries.responseStyle;
    case 'generated:preference:response-format':
      return t.memory.generatedSummaries.responseFormat;
    case 'generated:pattern:active-task-focus':
      return _localizeActiveTaskPatternBody(t, normalized);
  }

  return normalized;
}

String formatMemoryUpdatedLabel(
  Translations t, {
  required int updatedAtMs,
  DateTime? now,
}) {
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  if (updatedAtMs > nowMs) {
    return t.memory.meta.updatedOn(date: _formatMemoryDate(updatedAtMs));
  }

  final delta = nowMs - updatedAtMs;
  if (delta < const Duration(days: 1).inMilliseconds) {
    return t.memory.meta.updatedToday;
  }

  final dayCount = (delta / const Duration(days: 1).inMilliseconds).floor();
  if (dayCount <= 7) {
    return t.memory.meta.updatedDaysAgo(count: dayCount);
  }

  return t.memory.meta.updatedOn(date: _formatMemoryDate(updatedAtMs));
}

String? resolveMemorySectionLabel(
  Translations t, {
  required String? rawSectionLabel,
}) {
  final normalized = rawSectionLabel?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return switch (normalized) {
    'generated_preference' ||
    'generated_profile' ||
    'generated_event' ||
    'generated_pattern' =>
      t.memory.detail.sourceTitles.summary,
    _ => normalized,
  };
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
    'generated:event:decision' => t.memory.generatedTitles.decisionMemory,
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
        'response language',
        'response language preference',
      ],
    'generated:preference:response-style' => const <String>[
        'response style',
        'response style preference',
      ],
    'generated:preference:response-format' => const <String>[
        'response format',
        'response format preference',
      ],
    'generated:profile:self-profile' => const <String>[
        'self profile',
        'profile',
        'user profile',
      ],
    'generated:event:decision' => const <String>[
        'decision memory',
      ],
    _ => const <String>[],
  };
  return aliases.contains(normalized);
}

String? _extractGeneratedResponseLanguage(String text) {
  final match = RegExp(
    r'^User prefers responses in\s+(.+?)\.$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final rawLanguage = match.group(1)?.trim().toLowerCase();
  return switch (rawLanguage) {
    'chinese' => '中文',
    'english' => 'English',
    final value? when value.isNotEmpty => match.group(1)!.trim(),
    _ => null,
  };
}

String _localizeActiveTaskPatternBody(Translations t, String text) {
  final rawLines = text
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (rawLines.isEmpty) {
    return t.memory.generatedSummaries.activeTaskPattern;
  }

  const legacyPrefix = 'User is actively working across these task threads:';
  final lines = rawLines.first.trim() == legacyPrefix
      ? rawLines.skip(1).toList(growable: false)
      : rawLines;

  final localizedLines = <String>[
    t.memory.generatedSummaries.activeTaskPattern,
  ];
  final bulletPattern = RegExp(r'^-\s+(.*?)\s+\[([a-z_]+)\]\s*$');
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final match = bulletPattern.firstMatch(trimmed);
    if (match == null) {
      localizedLines.add(line);
      continue;
    }
    final title = match.group(1)!.trim();
    final status = match.group(2)!.trim();
    localizedLines.add('- $title [${_localizedTodoStatusLabel(t, status)}]');
  }
  return localizedLines.join('\n');
}

String _localizedTodoStatusLabel(Translations t, String status) {
  return switch (status.trim()) {
    'inbox' => t.actions.todoStatus.inbox,
    'open' => t.actions.todoStatus.open,
    'in_progress' => t.actions.todoStatus.inProgress,
    'done' => t.actions.todoStatus.done,
    'dismissed' => t.actions.todoStatus.dismissed,
    _ => status,
  };
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

String _formatMemoryDate(int updatedAtMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
