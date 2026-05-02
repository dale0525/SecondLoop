import 'secretary_models.dart';

String secretaryMemoryProposalSignature(SecretaryMemoryProposal proposal) {
  return secretaryMemorySignature(kind: proposal.kind, body: proposal.body);
}

String secretaryMemoryPageSignature(SecretaryMemoryPage page) {
  return secretaryMemorySignature(kind: page.kind, body: page.body);
}

String secretaryMemorySignature({
  required String kind,
  required String body,
}) {
  return '${_normalizeMemorySignaturePart(kind)}|'
      '${_normalizeMemorySignaturePart(body)}';
}

String _normalizeMemorySignaturePart(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[.。]+$'), '')
      .trim();
}

class MemoryProposalDetector {
  const MemoryProposalDetector();

  SecretaryMemoryProposal? detect({
    required String messageId,
    required String text,
    required int createdAtMs,
  }) {
    final trimmed = _normalize(text);
    if (trimmed.length < 6) return null;
    if (_looksLikeExternalAction(trimmed)) return null;

    final lower = trimmed.toLowerCase();
    final match = _matchIntent(lower, trimmed);
    if (match == null) return null;

    final body = _cleanMemoryBody(match.body);
    if (body.length < 4) return null;

    return SecretaryMemoryProposal(
      id: 'memory-proposal-$messageId',
      sourceMessageId: messageId,
      kind: match.kind,
      title: _titleFromBody(body),
      body: body,
      confidence: match.confidence,
      createdAtMs: createdAtMs,
      actionHint: match.actionHint,
    );
  }

  _MemoryIntentMatch? _matchIntent(String lower, String original) {
    final rememberPatterns = <String>[
      'remember that',
      'please remember',
      '记住',
      '请记住',
    ];
    for (final pattern in rememberPatterns) {
      final index = lower.indexOf(pattern);
      if (index < 0) continue;
      final body = original.substring(index + pattern.length);
      return _MemoryIntentMatch(
        kind: _kindFor(body),
        body: body,
        confidence: 0.88,
      );
    }

    final preferencePatterns = <String>[
      'i prefer',
      'my preference is',
      '我更喜欢',
      '我的偏好',
    ];
    for (final pattern in preferencePatterns) {
      if (!lower.contains(pattern)) continue;
      return _MemoryIntentMatch(
        kind: 'preference',
        body: original,
        confidence: 0.82,
      );
    }

    final replacementPatterns = <String>[
      'i no longer',
      'actually',
      '我不再',
      '其实',
      '实际上',
    ];
    for (final pattern in replacementPatterns) {
      if (!lower.contains(pattern)) continue;
      return _MemoryIntentMatch(
        kind: _kindFor(original),
        body: original,
        confidence: 0.8,
        actionHint: 'update',
      );
    }

    return null;
  }

  String _kindFor(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('prefer') ||
        lower.contains('preference') ||
        lower.contains('更喜欢') ||
        lower.contains('偏好')) {
      return 'preference';
    }
    if (lower.contains('habit') || lower.contains('routine')) {
      return 'habit';
    }
    if (lower.contains('project') || lower.contains('项目')) {
      return 'project';
    }
    return 'fact';
  }

  String _cleanMemoryBody(String text) {
    return _normalize(
      text
          .replaceFirst(RegExp(r'^[\s,，:：]+'), '')
          .replaceFirst(RegExp(r'[.。]+$'), ''),
    );
  }

  String _titleFromBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 36) return compact;
    return '${compact.substring(0, 33).trimRight()}...';
  }

  bool _looksLikeExternalAction(String text) {
    final lower = text.toLowerCase();
    const blocked = <String>[
      'send ',
      'email ',
      'book ',
      'pay ',
      'message ',
      'call ',
      '发送',
      '发给',
      '预订',
      '付款',
    ];
    return blocked.any(lower.startsWith);
  }

  String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _MemoryIntentMatch {
  const _MemoryIntentMatch({
    required this.kind,
    required this.body,
    required this.confidence,
    this.actionHint = 'propose',
  });

  final String kind;
  final String body;
  final double confidence;
  final String actionHint;
}
