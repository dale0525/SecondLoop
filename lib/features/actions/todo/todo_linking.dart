class TodoLinkTarget {
  const TodoLinkTarget({
    required this.id,
    required this.title,
    required this.status,
    this.dueLocal,
  });

  final String id;
  final String title;
  final String status;
  final DateTime? dueLocal;
}

class TodoLinkCandidate {
  const TodoLinkCandidate({
    required this.target,
    required this.score,
  });

  final TodoLinkTarget target;
  final int score;
}

class TodoUpdateIntent {
  const TodoUpdateIntent({
    required this.newStatus,
    required this.isExplicit,
  });

  final String newStatus; // "in_progress" | "done" | "dismissed"
  final bool isExplicit;
}

TodoUpdateIntent inferTodoUpdateIntent(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) {
    return const TodoUpdateIntent(newStatus: 'in_progress', isExplicit: false);
  }

  bool containsAny(List<String> needles) =>
      needles.any((n) => n.isNotEmpty && t.contains(n));

  final hasNegation = t.contains('还没') ||
      t.contains('沒') ||
      t.contains('没') ||
      t.contains("haven't") ||
      t.contains('not');

  final dismissKeywords = <String>[
    '取消',
    '不做了',
    '算了',
    '不用了',
    '别提醒',
    '删掉',
    '删除',
    // ja
    'キャンセル',
    '中止',
    'やめた',
    '不要',
    '削除',
    // ko
    '취소',
    '삭제',
    '그만',
    // es
    'cancelar',
    'cancela',
    'borrar',
    'eliminar',
    // fr
    'annuler',
    'supprimer',
    // de
    'abbrechen',
    'löschen',
    'loeschen',
    'streichen',
    'dismiss',
    'delete',
    'cancel',
  ];

  final doneKeywords = <String>[
    '做完',
    '完成',
    '搞定',
    // ja
    '完了',
    '完了した',
    '終わった',
    '完了',
    // ko
    '완료',
    '끝냈',
    '끝남',
    // es
    'hecho',
    'lista',
    'listo',
    'terminado',
    'completado',
    // fr
    'fait',
    'fini',
    'terminé',
    'termine',
    'complété',
    'complete',
    // de
    'fertig',
    'erledigt',
    'abgeschlossen',
    'done',
    'finished',
    'complete',
    'completed',
    '✅',
    '✔',
  ];

  final progressKeywords = <String>[
    '开始',
    '在做',
    '进行中',
    '接到',
    '接到了',
    '见到',
    '到场',
    '已到',
    // ja
    '開始',
    '始めた',
    '進行中',
    // ko
    '시작',
    '진행중',
    '하는 중',
    // es
    'empecé',
    'empezar',
    'en progreso',
    'trabajando en',
    // fr
    'commencé',
    'en cours',
    // de
    'begonnen',
    'in arbeit',
    'arbeite an',
    'arrived',
    'started',
    'in progress',
    'working on',
  ];

  if (containsAny(dismissKeywords)) {
    return const TodoUpdateIntent(newStatus: 'dismissed', isExplicit: true);
  }

  if (containsAny(doneKeywords)) {
    if (hasNegation) {
      return const TodoUpdateIntent(newStatus: 'in_progress', isExplicit: true);
    }
    return const TodoUpdateIntent(newStatus: 'done', isExplicit: true);
  }

  if (containsAny(progressKeywords)) {
    return const TodoUpdateIntent(newStatus: 'in_progress', isExplicit: true);
  }

  // Default: treat as a progress update, but not explicit.
  return const TodoUpdateIntent(newStatus: 'in_progress', isExplicit: false);
}

List<TodoLinkCandidate> rankTodoCandidates(
  String message,
  List<TodoLinkTarget> todos, {
  required DateTime nowLocal,
  int limit = 5,
}) {
  final queryNorm = _normalizeText(message);
  final queryCompact = _compactText(queryNorm);
  if (queryCompact.isEmpty) return const <TodoLinkCandidate>[];

  final queryRunes = queryCompact.runes.toList(growable: false);
  final queryBigrams = _collectBigrams(queryRunes);
  final queryTrigrams = _collectTrigrams(queryRunes);

  final candidates = <TodoLinkCandidate>[];
  for (final todo in todos) {
    if (todo.status == 'done' || todo.status == 'dismissed') continue;
    final score = _liteScore(
          queryNorm: queryNorm,
          queryCompact: queryCompact,
          queryBigrams: queryBigrams,
          queryTrigrams: queryTrigrams,
          candidate: todo.title,
        ) +
        _dueBoost(todo.dueLocal, nowLocal);
    if (score <= 0) continue;
    candidates.add(TodoLinkCandidate(target: todo, score: score));
  }

  candidates.sort((a, b) => b.score.compareTo(a.score));
  if (candidates.length <= limit) return candidates;
  return candidates.sublist(0, limit);
}

int _dueBoost(DateTime? dueLocal, DateTime nowLocal) {
  if (dueLocal == null) return 0;
  final diffMinutes = dueLocal.difference(nowLocal).inMinutes.abs();
  if (diffMinutes <= 120) return 1500;
  if (diffMinutes <= 360) return 800;
  if (diffMinutes <= 1440) return 200;
  return 0;
}

String _normalizeText(String text) {
  final trimmed = text.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceAll(RegExp(r'\s+'), ' ');
}

String _compactText(String text) => text.replaceAll(RegExp(r'\s+'), '');

Set<int> _collectBigrams(List<int> runes) {
  final out = <int>{};
  if (runes.length < 2) return out;
  for (var i = 0; i < runes.length - 1; i++) {
    final a = runes[i];
    final b = runes[i + 1];
    out.add((a << 32) | b);
  }
  return out;
}

Set<int> _collectTrigrams(List<int> runes) {
  final out = <int>{};
  if (runes.length < 3) return out;
  for (var i = 0; i < runes.length - 2; i++) {
    final a = runes[i];
    final b = runes[i + 1];
    final c = runes[i + 2];
    out.add((a << 64) | (b << 32) | c);
  }
  return out;
}

int _liteScore({
  required String queryNorm,
  required String queryCompact,
  required Set<int> queryBigrams,
  required Set<int> queryTrigrams,
  required String candidate,
}) {
  final candNorm = _normalizeText(candidate);
  if (candNorm.isEmpty) return 0;

  final candCompact = _compactText(candNorm);
  if (candCompact.isEmpty) return 0;

  var score = 0;

  if (candNorm == queryNorm) {
    score += 10000;
  }

  if (queryNorm.isNotEmpty && candNorm.contains(queryNorm)) {
    score += 500;
    score += queryCompact.runes.length * 50;
  }

  for (final token in queryNorm.split(' ')) {
    if (token.runes.length < 2) continue;
    if (candNorm.contains(token)) {
      score += token.runes.length * 200;
    }
  }

  final candRunes = candCompact.runes.toList(growable: false);
  if (queryBigrams.isNotEmpty) {
    final candBigrams = _collectBigrams(candRunes);
    final overlap = queryBigrams.where((b) => candBigrams.contains(b)).length;
    score += overlap * 50;
  }

  if (queryTrigrams.isNotEmpty) {
    final candTrigrams = _collectTrigrams(candRunes);
    final overlap = queryTrigrams.where((t) => candTrigrams.contains(t)).length;
    score += overlap * 80;
  }

  return score;
}
