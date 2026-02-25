const Duration kAudioRecordingRecoveryMaxAge = Duration(hours: 24);
const int kAudioRecordingRecoverySchemaVersion = 1;

List<String> mergeRecordedAudioRecoverySegmentPaths(
  List<String> completedPaths, {
  String? activePath,
}) {
  final known = <String>{};
  final ordered = <String>[];

  for (final path in completedPaths) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) continue;
    if (known.add(trimmed)) {
      ordered.add(trimmed);
    }
  }

  final active = activePath?.trim();
  if (active != null && active.isNotEmpty && known.add(active)) {
    ordered.add(active);
  }

  return ordered;
}

final class RecordedAudioRecoverySnapshot {
  RecordedAudioRecoverySnapshot({
    required this.sessionId,
    required this.startedAtMs,
    required this.createdAtMs,
    required this.conversationId,
    required this.activeSegmentPath,
    required List<String> completedSegmentPaths,
    required this.schemaVersion,
  }) : completedSegmentPaths = List<String>.unmodifiable(
          mergeRecordedAudioRecoverySegmentPaths(completedSegmentPaths),
        );

  final String sessionId;
  final int startedAtMs;
  final int createdAtMs;
  final String conversationId;
  final String? activeSegmentPath;
  final List<String> completedSegmentPaths;
  final int schemaVersion;

  List<String> get recoverableSegmentPaths {
    return mergeRecordedAudioRecoverySegmentPaths(
      completedSegmentPaths,
      activePath: activeSegmentPath,
    );
  }

  bool isRecoverable({
    DateTime? now,
    Duration maxAge = kAudioRecordingRecoveryMaxAge,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      createdAtMs,
      isUtc: false,
    );
    if (effectiveNow.difference(createdAt) > maxAge) {
      return false;
    }
    return recoverableSegmentPaths.isNotEmpty;
  }

  RecordedAudioRecoverySnapshot copyWith({
    String? activeSegmentPath,
    List<String>? completedSegmentPaths,
  }) {
    return RecordedAudioRecoverySnapshot(
      sessionId: sessionId,
      startedAtMs: startedAtMs,
      createdAtMs: createdAtMs,
      conversationId: conversationId,
      activeSegmentPath: activeSegmentPath,
      completedSegmentPaths:
          completedSegmentPaths ?? this.completedSegmentPaths,
      schemaVersion: schemaVersion,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'session_id': sessionId,
      'started_at_ms': startedAtMs,
      'created_at_ms': createdAtMs,
      'conversation_id': conversationId,
      'active_segment_path': activeSegmentPath,
      'completed_segment_paths': completedSegmentPaths,
      'schema_version': schemaVersion,
    };
  }

  static RecordedAudioRecoverySnapshot? tryFromJson(Map<String, Object?> json) {
    try {
      final sessionId = (json['session_id'] as String?)?.trim() ?? '';
      final startedAtMs = (json['started_at_ms'] as num?)?.toInt() ?? 0;
      final createdAtMs = (json['created_at_ms'] as num?)?.toInt() ?? 0;
      final conversationId = (json['conversation_id'] as String?)?.trim() ?? '';
      final schemaVersion = (json['schema_version'] as num?)?.toInt() ?? 0;

      if (sessionId.isEmpty ||
          startedAtMs <= 0 ||
          createdAtMs <= 0 ||
          conversationId.isEmpty ||
          schemaVersion != kAudioRecordingRecoverySchemaVersion) {
        return null;
      }

      final completedRaw = json['completed_segment_paths'];
      final completed = <String>[];
      if (completedRaw is List) {
        for (final item in completedRaw) {
          if (item is String) {
            final trimmed = item.trim();
            if (trimmed.isNotEmpty) {
              completed.add(trimmed);
            }
          }
        }
      }

      final activePath = (json['active_segment_path'] as String?)?.trim();

      return RecordedAudioRecoverySnapshot(
        sessionId: sessionId,
        startedAtMs: startedAtMs,
        createdAtMs: createdAtMs,
        conversationId: conversationId,
        activeSegmentPath:
            activePath == null || activePath.isEmpty ? null : activePath,
        completedSegmentPaths: completed,
        schemaVersion: schemaVersion,
      );
    } catch (_) {
      return null;
    }
  }
}
