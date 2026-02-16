part of 'video_kind_classifier.dart';

Map<String, int> _scoreKindsByKeywords(
  Iterable<String> texts,
  List<_VideoKindKeywordRule> rules,
) {
  final scoreByKind = <String, int>{};
  for (final rawText in texts) {
    final text = rawText.trim().toLowerCase();
    if (text.isEmpty) continue;

    for (final rule in rules) {
      final score = _countKeywordScore(text, rule.keywords);
      if (score <= 0) continue;
      scoreByKind.update(
        rule.kind,
        (value) => value + score,
        ifAbsent: () => score,
      );
    }
  }
  return scoreByKind;
}

int _countKeywordScore(String text, List<String> keywords) {
  var score = 0;
  for (final keyword in keywords) {
    if (!_containsKeyword(text, keyword)) continue;
    score += _keywordWeight(keyword);
  }
  return score;
}

bool _containsKeyword(String text, String keyword) {
  final normalizedText = text.trim().toLowerCase();
  final normalizedKeyword = keyword.trim().toLowerCase();
  if (normalizedText.isEmpty || normalizedKeyword.isEmpty) {
    return false;
  }

  if (normalizedKeyword.contains(' ')) {
    return normalizedText.contains(normalizedKeyword);
  }

  final asciiWord = RegExp(r'^[a-z0-9_]+$').hasMatch(normalizedKeyword);
  if (!asciiWord) {
    return normalizedText.contains(normalizedKeyword);
  }

  final words = normalizedText.split(RegExp(r'[^a-z0-9_]+'));
  for (final word in words) {
    if (word == normalizedKeyword) {
      return true;
    }
  }
  return false;
}

int _keywordWeight(String keyword) {
  final normalized = keyword.trim();
  if (normalized.isEmpty) return 0;
  if (normalized.contains(' ')) return 2;
  final asciiOnly = RegExp(r'^[\x00-\x7F]+$').hasMatch(normalized);
  if (!asciiOnly && normalized.length >= 2) return 2;
  if (normalized.length >= 8) return 2;
  return 1;
}

void _applyCompositeTextSignals(Map<String, int> scoreByKind, String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) return;

  final hasQaMarkers = normalized.contains('q:') && normalized.contains('a:');
  final hasInterviewPair = (_containsKeyword(normalized, 'pregunta') &&
          _containsKeyword(normalized, 'respuesta') ||
      _containsKeyword(normalized, 'frage') &&
          _containsKeyword(normalized, 'antwort') ||
      _containsKeyword(normalized, 'question') &&
          _containsKeyword(normalized, 'réponse') ||
      _containsKeyword(normalized, 'domanda') &&
          _containsKeyword(normalized, 'risposta') ||
      _containsKeyword(normalized, 'вопрос') &&
          _containsKeyword(normalized, 'ответ') ||
      _containsKeyword(normalized, 'سؤال') &&
          _containsKeyword(normalized, 'جواب') ||
      _containsKeyword(normalized, 'प्रश्न') &&
          _containsKeyword(normalized, 'उत्तर'));
  if (hasQaMarkers || hasInterviewPair) {
    _bumpKindScore(scoreByKind, kVideoKindInterview, 3);
  }

  final hasMeetingHeader = _containsKeyword(normalized, 'agenda') ||
      _containsKeyword(normalized, 'meeting notes') ||
      _containsKeyword(normalized, 'reunion') ||
      _containsKeyword(normalized, 'réunion') ||
      _containsKeyword(normalized, 'besprechung') ||
      _containsKeyword(normalized, 'riunione') ||
      _containsKeyword(normalized, 'встреча') ||
      _containsKeyword(normalized, 'اجتماع') ||
      _containsKeyword(normalized, 'बैठक') ||
      _containsKeyword(normalized, '会議') ||
      _containsKeyword(normalized, '회의');
  final hasMeetingActions = _containsKeyword(normalized, 'action items') ||
      _containsKeyword(normalized, 'next steps') ||
      _containsKeyword(normalized, 'blockers') ||
      _containsKeyword(normalized, 'acciones') ||
      _containsKeyword(normalized, 'prochaines étapes') ||
      _containsKeyword(normalized, 'nächste schritte') ||
      _containsKeyword(normalized, 'azioni') ||
      _containsKeyword(normalized, 'повестка') ||
      _containsKeyword(normalized, 'جدول الأعمال') ||
      _containsKeyword(normalized, 'कार्यसूची') ||
      _containsKeyword(normalized, '待办');
  if (hasMeetingHeader && hasMeetingActions) {
    _bumpKindScore(scoreByKind, kVideoKindMeeting, 3);
  }

  final hasTutorialStep = _containsKeyword(normalized, 'step 1') ||
      _containsKeyword(normalized, '步骤') ||
      _containsKeyword(normalized, 'paso 1') ||
      _containsKeyword(normalized, 'étape 1') ||
      _containsKeyword(normalized, 'schritt 1') ||
      _containsKeyword(normalized, 'passo 1') ||
      _containsKeyword(normalized, 'passo a passo') ||
      _containsKeyword(normalized, '手順') ||
      _containsKeyword(normalized, 'कदम');
  final hasTutorialAction = _containsKeyword(normalized, 'install') ||
      _containsKeyword(normalized, 'setup') ||
      _containsKeyword(normalized, 'configure') ||
      _containsKeyword(normalized, 'instalar') ||
      _containsKeyword(normalized, 'installer') ||
      _containsKeyword(normalized, 'installieren') ||
      _containsKeyword(normalized, 'guida') ||
      _containsKeyword(normalized, 'руководство') ||
      _containsKeyword(normalized, 'تعليمات') ||
      _containsKeyword(normalized, 'ट्यूटोरियल');
  if (hasTutorialStep && hasTutorialAction) {
    _bumpKindScore(scoreByKind, kVideoKindTutorial, 3);
  }

  final hasLectureHeader = _containsKeyword(normalized, 'lecture') ||
      _containsKeyword(normalized, 'chapter') ||
      _containsKeyword(normalized, 'lección') ||
      _containsKeyword(normalized, 'cours') ||
      _containsKeyword(normalized, 'vorlesung') ||
      _containsKeyword(normalized, 'aula') ||
      _containsKeyword(normalized, 'lezione') ||
      _containsKeyword(normalized, 'лекция') ||
      _containsKeyword(normalized, 'محاضرة') ||
      _containsKeyword(normalized, 'व्याख्यान') ||
      _containsKeyword(normalized, '講義') ||
      _containsKeyword(normalized, '강의');
  final hasLectureHomework = _containsKeyword(normalized, 'assignment') ||
      _containsKeyword(normalized, 'homework') ||
      _containsKeyword(normalized, 'semester') ||
      _containsKeyword(normalized, 'hausaufgabe') ||
      _containsKeyword(normalized, 'aufgabe') ||
      _containsKeyword(normalized, 'домашнее задание') ||
      _containsKeyword(normalized, 'واجب') ||
      _containsKeyword(normalized, '課題') ||
      _containsKeyword(normalized, 'होमवर्क');
  if (hasLectureHeader && hasLectureHomework) {
    _bumpKindScore(scoreByKind, kVideoKindLecture, 3);
  }

  final hasPresentationHeader = _containsKeyword(normalized, 'slide') ||
      _containsKeyword(normalized, 'roadmap') ||
      _containsKeyword(normalized, 'presentación') ||
      _containsKeyword(normalized, 'présentation') ||
      _containsKeyword(normalized, 'präsentation') ||
      _containsKeyword(normalized, 'apresentação') ||
      _containsKeyword(normalized, 'presentazione') ||
      _containsKeyword(normalized, 'презентация') ||
      _containsKeyword(normalized, 'عرض تقديمي') ||
      _containsKeyword(normalized, 'प्रस्तुति') ||
      _containsKeyword(normalized, 'プレゼン') ||
      _containsKeyword(normalized, '발표');
  final hasPresentationMetrics = _containsKeyword(normalized, 'kpi') ||
      _containsKeyword(normalized, 'revenue') ||
      _containsKeyword(normalized, 'summary') ||
      _containsKeyword(normalized, 'resumen') ||
      _containsKeyword(normalized, 'résumé') ||
      _containsKeyword(normalized, 'zusammenfassung') ||
      _containsKeyword(normalized, 'umsatz') ||
      _containsKeyword(normalized, 'итоги') ||
      _containsKeyword(normalized, 'ملخص') ||
      _containsKeyword(normalized, 'सारांश');
  if (hasPresentationHeader && hasPresentationMetrics) {
    _bumpKindScore(scoreByKind, kVideoKindPresentation, 3);
  }

  final hasGameplayHeader = _containsKeyword(normalized, 'level') ||
      _containsKeyword(normalized, 'quest') ||
      _containsKeyword(normalized, 'nivel') ||
      _containsKeyword(normalized, 'niveau') ||
      _containsKeyword(normalized, 'stufe') ||
      _containsKeyword(normalized, 'ステージ') ||
      _containsKeyword(normalized, 'геймплей') ||
      _containsKeyword(normalized, 'لعبة') ||
      _containsKeyword(normalized, 'गेमप्ले');
  final hasGameplaySignals = _containsKeyword(normalized, 'boss') ||
      _containsKeyword(normalized, 'damage') ||
      _containsKeyword(normalized, 'kill') ||
      _containsKeyword(normalized, 'puntaje') ||
      _containsKeyword(normalized, 'punkte') ||
      _containsKeyword(normalized, 'placar') ||
      _containsKeyword(normalized, 'punteggio') ||
      _containsKeyword(normalized, 'урон') ||
      _containsKeyword(normalized, 'ضرر') ||
      _containsKeyword(normalized, 'स्कोर');
  if (hasGameplayHeader && hasGameplaySignals) {
    _bumpKindScore(scoreByKind, kVideoKindGameplay, 3);
  }

  final hasDesktopContext = _containsKeyword(normalized, 'terminal') ||
      _containsKeyword(normalized, 'browser') ||
      _containsKeyword(normalized, 'navegador') ||
      _containsKeyword(normalized, 'navigateur') ||
      _containsKeyword(normalized, 'терминал') ||
      _containsKeyword(normalized, 'متصفح') ||
      _containsKeyword(normalized, 'टर्मिनल') ||
      _containsKeyword(normalized, 'ターミナル');
  final hasDesktopUiMarkers = _containsKeyword(normalized, 'window') ||
      _containsKeyword(normalized, 'tab') ||
      _containsKeyword(normalized, 'cursor') ||
      _containsKeyword(normalized, 'fenster') ||
      _containsKeyword(normalized, 'fenêtre') ||
      _containsKeyword(normalized, 'janela') ||
      _containsKeyword(normalized, 'نافذة') ||
      _containsKeyword(normalized, 'браузер') ||
      _containsKeyword(normalized, '브라우저');
  if (hasDesktopContext && hasDesktopUiMarkers) {
    _bumpKindScore(scoreByKind, kVideoKindScreenRecording, 2);
  }
}

void _bumpKindScore(Map<String, int> scoreByKind, String kind, int delta) {
  if (delta <= 0) return;
  scoreByKind.update(kind, (value) => value + delta, ifAbsent: () => delta);
}

String? _selectBestKindByScore(
  Map<String, int> scoreByKind,
  List<_VideoKindKeywordRule> orderedRules, {
  required int minScore,
}) {
  if (scoreByKind.isEmpty) return null;

  String? bestKind;
  var bestScore = minScore - 1;
  var bestPriority = orderedRules.length + 1;

  for (var i = 0; i < orderedRules.length; i++) {
    final kind = orderedRules[i].kind;
    final score = scoreByKind[kind] ?? 0;
    if (score < minScore) continue;

    if (score > bestScore || (score == bestScore && i < bestPriority)) {
      bestKind = kind;
      bestScore = score;
      bestPriority = i;
    }
  }

  return bestKind;
}

_VideoKindKeywordRule? _lookupRuleByKind(
  List<_VideoKindKeywordRule> rules,
  String kind,
) {
  for (final rule in rules) {
    if (rule.kind == kind) return rule;
  }
  return null;
}

double _confidenceFromKeywordScore(
  double base,
  int score, {
  double step = 0.04,
  double max = 0.92,
}) {
  if (score <= 1) return base.clamp(0.0, max).toDouble();
  final bonus = (score - 1) * step;
  return (base + bonus).clamp(0.0, max).toDouble();
}

String _normalizeWhitespace(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

int _countMeaningfulChars(String text) {
  if (text.isEmpty) return 0;
  final matches = RegExp(
    r'[A-Za-z0-9\u00C0-\u024F\u0400-\u04FF\u0600-\u06FF\u0900-\u097F\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]',
  ).allMatches(text);
  return matches.length;
}
