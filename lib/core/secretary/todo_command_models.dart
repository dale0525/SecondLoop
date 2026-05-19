enum SecretaryTodoCommandKind {
  create,
  updateTitle,
  reschedule,
  setStatus,
  dismiss,
  reprioritize,
  batchUpdate,
  none,
}

enum SecretaryTodoCommandRoute {
  local,
  cloud,
}

final class SecretaryTodoCommand {
  const SecretaryTodoCommand({
    required this.id,
    required this.kind,
    required this.route,
    required this.confidence,
    required this.sourceMessageId,
    this.targetTodoId,
    this.targetTitle,
    this.newTitle,
    this.newStatus,
    this.dueAtMs,
    this.manualImportanceNudgeScore,
    this.manualUrgencyNudgeScore,
    this.reason,
    this.rawText,
  });

  final String id;
  final SecretaryTodoCommandKind kind;
  final SecretaryTodoCommandRoute route;
  final double confidence;
  final String sourceMessageId;
  final String? targetTodoId;
  final String? targetTitle;
  final String? newTitle;
  final String? newStatus;
  final int? dueAtMs;
  final int? manualImportanceNudgeScore;
  final int? manualUrgencyNudgeScore;
  final String? reason;
  final String? rawText;

  bool get isValid {
    if (id.trim().isEmpty || sourceMessageId.trim().isEmpty) return false;
    if (!confidence.isFinite || confidence < 0 || confidence > 1) return false;

    final hasTarget = _hasText(targetTodoId);
    switch (kind) {
      case SecretaryTodoCommandKind.create:
        return _hasText(newTitle) || _hasText(targetTitle);
      case SecretaryTodoCommandKind.updateTitle:
        return hasTarget && _hasText(newTitle);
      case SecretaryTodoCommandKind.reschedule:
        return hasTarget && dueAtMs != null;
      case SecretaryTodoCommandKind.setStatus:
        return hasTarget && _canonicalStatus(newStatus) != null;
      case SecretaryTodoCommandKind.dismiss:
        return hasTarget;
      case SecretaryTodoCommandKind.reprioritize:
        return hasTarget &&
            (manualImportanceNudgeScore != null ||
                manualUrgencyNudgeScore != null);
      case SecretaryTodoCommandKind.batchUpdate:
        return true;
      case SecretaryTodoCommandKind.none:
        return false;
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': _kindToWire(kind),
      'route': _routeToWire(route),
      'confidence': confidence,
      'source_message_id': sourceMessageId,
      'target_todo_id': targetTodoId,
      'target_title': targetTitle,
      'new_title': newTitle,
      'new_status': newStatus,
      'due_at_ms': dueAtMs,
      'manual_importance_nudge_score': manualImportanceNudgeScore,
      'manual_urgency_nudge_score': manualUrgencyNudgeScore,
      'reason': reason,
      'raw_text': rawText,
    };
  }

  factory SecretaryTodoCommand.fromJson(Map<Object?, Object?> json) {
    return SecretaryTodoCommand(
      id: _stringValue(json['id']) ?? '',
      kind: _kindFromWire(_stringValue(json['kind'])),
      route: _routeFromWire(_stringValue(json['route'])),
      confidence: _doubleValue(json['confidence']) ?? 0,
      sourceMessageId: _stringValue(json['source_message_id']) ??
          _stringValue(json['sourceMessageId']) ??
          '',
      targetTodoId: _stringValue(json['target_todo_id']) ??
          _stringValue(json['targetTodoId']),
      targetTitle: _stringValue(json['target_title']) ??
          _stringValue(json['targetTitle']),
      newTitle:
          _stringValue(json['new_title']) ?? _stringValue(json['newTitle']),
      newStatus:
          _stringValue(json['new_status']) ?? _stringValue(json['newStatus']),
      dueAtMs: _intValue(json['due_at_ms']) ?? _intValue(json['dueAtMs']),
      manualImportanceNudgeScore:
          _intValue(json['manual_importance_nudge_score']) ??
              _intValue(json['manualImportanceNudgeScore']),
      manualUrgencyNudgeScore: _intValue(json['manual_urgency_nudge_score']) ??
          _intValue(json['manualUrgencyNudgeScore']),
      reason: _stringValue(json['reason']),
      rawText: _stringValue(json['raw_text']) ?? _stringValue(json['rawText']),
    );
  }

  SecretaryTodoCommand copyWith({
    String? id,
    SecretaryTodoCommandKind? kind,
    SecretaryTodoCommandRoute? route,
    double? confidence,
    String? sourceMessageId,
    String? targetTodoId,
    String? targetTitle,
    String? newTitle,
    String? newStatus,
    int? dueAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
    String? reason,
    String? rawText,
    bool clearTargetTodoId = false,
    bool clearTargetTitle = false,
    bool clearNewTitle = false,
    bool clearNewStatus = false,
    bool clearDueAtMs = false,
    bool clearManualImportanceNudgeScore = false,
    bool clearManualUrgencyNudgeScore = false,
    bool clearReason = false,
    bool clearRawText = false,
  }) {
    return SecretaryTodoCommand(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      route: route ?? this.route,
      confidence: confidence ?? this.confidence,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      targetTodoId:
          clearTargetTodoId ? null : (targetTodoId ?? this.targetTodoId),
      targetTitle: clearTargetTitle ? null : (targetTitle ?? this.targetTitle),
      newTitle: clearNewTitle ? null : (newTitle ?? this.newTitle),
      newStatus: clearNewStatus ? null : (newStatus ?? this.newStatus),
      dueAtMs: clearDueAtMs ? null : (dueAtMs ?? this.dueAtMs),
      manualImportanceNudgeScore: clearManualImportanceNudgeScore
          ? null
          : (manualImportanceNudgeScore ?? this.manualImportanceNudgeScore),
      manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
          ? null
          : (manualUrgencyNudgeScore ?? this.manualUrgencyNudgeScore),
      reason: clearReason ? null : (reason ?? this.reason),
      rawText: clearRawText ? null : (rawText ?? this.rawText),
    );
  }
}

String _kindToWire(SecretaryTodoCommandKind kind) {
  return switch (kind) {
    SecretaryTodoCommandKind.create => 'create',
    SecretaryTodoCommandKind.updateTitle => 'update_title',
    SecretaryTodoCommandKind.reschedule => 'reschedule',
    SecretaryTodoCommandKind.setStatus => 'set_status',
    SecretaryTodoCommandKind.dismiss => 'dismiss',
    SecretaryTodoCommandKind.reprioritize => 'reprioritize',
    SecretaryTodoCommandKind.batchUpdate => 'batch_update',
    SecretaryTodoCommandKind.none => 'none',
  };
}

SecretaryTodoCommandKind _kindFromWire(String? value) {
  return switch ((value ?? '').trim()) {
    'create' => SecretaryTodoCommandKind.create,
    'update_title' || 'updateTitle' => SecretaryTodoCommandKind.updateTitle,
    'reschedule' => SecretaryTodoCommandKind.reschedule,
    'set_status' || 'setStatus' => SecretaryTodoCommandKind.setStatus,
    'dismiss' || 'delete' => SecretaryTodoCommandKind.dismiss,
    'reprioritize' => SecretaryTodoCommandKind.reprioritize,
    'batch_update' || 'batchUpdate' => SecretaryTodoCommandKind.batchUpdate,
    _ => SecretaryTodoCommandKind.none,
  };
}

String _routeToWire(SecretaryTodoCommandRoute route) {
  return switch (route) {
    SecretaryTodoCommandRoute.local => 'local',
    SecretaryTodoCommandRoute.cloud => 'cloud',
  };
}

SecretaryTodoCommandRoute _routeFromWire(String? value) {
  return switch ((value ?? '').trim()) {
    'cloud' || 'cloud_gateway' => SecretaryTodoCommandRoute.cloud,
    _ => SecretaryTodoCommandRoute.local,
  };
}

String? _canonicalStatus(String? value) {
  return switch ((value ?? '').trim()) {
    'in_progress' || 'done' || 'dismissed' || 'open' || 'inbox' => value,
    _ => null,
  };
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String? _stringValue(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
