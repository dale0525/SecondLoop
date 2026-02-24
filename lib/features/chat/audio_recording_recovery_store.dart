import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'audio_recording_recovery_snapshot.dart';

final class AudioRecordingRecoveryStore {
  static const String _snapshotPrefsKey = 'chat_audio_recording_recovery_v1';

  static Future<void> beginSession({
    required String sessionId,
    required int startedAtMs,
    required String conversationId,
    int? createdAtMs,
  }) async {
    final snapshot = RecordedAudioRecoverySnapshot(
      sessionId: sessionId,
      startedAtMs: startedAtMs,
      createdAtMs: createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      conversationId: conversationId,
      activeSegmentPath: null,
      completedSegmentPaths: const <String>[],
      schemaVersion: kAudioRecordingRecoverySchemaVersion,
    );
    await _saveSnapshot(snapshot);
  }

  static Future<void> markActiveSegment({
    required String sessionId,
    required String path,
  }) async {
    final snapshot = await loadSnapshot();
    if (snapshot == null || snapshot.sessionId != sessionId) return;

    final next = snapshot.copyWith(activeSegmentPath: path);
    await _saveSnapshot(next);
  }

  static Future<void> markSegmentCompleted({
    required String sessionId,
    String? path,
  }) async {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    final snapshot = await loadSnapshot();
    if (snapshot == null || snapshot.sessionId != sessionId) return;

    final nextCompleted = mergeRecordedAudioRecoverySegmentPaths(
      snapshot.completedSegmentPaths,
      activePath: trimmed,
    );

    final next = snapshot.copyWith(
      activeSegmentPath: snapshot.activeSegmentPath == trimmed
          ? null
          : snapshot.activeSegmentPath,
      completedSegmentPaths: nextCompleted,
    );
    await _saveSnapshot(next);
  }

  static Future<RecordedAudioRecoverySnapshot?> loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotPrefsKey)?.trim();
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return RecordedAudioRecoverySnapshot.tryFromJson(
        decoded.cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<RecordedAudioRecoverySnapshot?> loadRecoverableSession({
    DateTime? now,
    Duration maxAge = kAudioRecordingRecoveryMaxAge,
  }) async {
    final snapshot = await loadSnapshot();
    if (snapshot == null) return null;
    if (!snapshot.isRecoverable(now: now, maxAge: maxAge)) {
      await clearSession(expectedSessionId: snapshot.sessionId);
      return null;
    }
    return snapshot;
  }

  static Future<void> clearSession({
    String? expectedSessionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (expectedSessionId == null || expectedSessionId.trim().isEmpty) {
      await prefs.remove(_snapshotPrefsKey);
      return;
    }

    final snapshot = await loadSnapshot();
    if (snapshot == null) return;
    if (snapshot.sessionId != expectedSessionId.trim()) return;
    await prefs.remove(_snapshotPrefsKey);
  }

  static Future<void> _saveSnapshot(
    RecordedAudioRecoverySnapshot snapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotPrefsKey, jsonEncode(snapshot.toJson()));
  }
}
