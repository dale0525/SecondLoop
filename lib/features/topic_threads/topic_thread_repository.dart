import 'package:flutter/foundation.dart';

import '../../core/backend/native_app_dir.dart';
import '../../src/rust/api/topic_threads.dart' as rust_topic_threads;
import '../../src/rust/db.dart';

class TopicThreadRepository {
  const TopicThreadRepository();

  Future<String?> _resolveAppDirOrNull() async {
    if (kIsWeb) return null;
    try {
      return await getNativeAppDir();
    } catch (_) {
      return null;
    }
  }

  Future<String> _requireAppDir() async {
    final appDir = await _resolveAppDirOrNull();
    if (appDir == null || appDir.isEmpty) {
      throw StateError('native_app_dir_not_available');
    }
    return appDir;
  }

  Future<List<TopicThread>> listTopicThreads(
    Uint8List key,
    String conversationId,
  ) async {
    final appDir = await _resolveAppDirOrNull();
    if (appDir == null) return const <TopicThread>[];
    return rust_topic_threads.dbListTopicThreads(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
    );
  }

  Future<TopicThread> createTopicThread(
    Uint8List key,
    String conversationId, {
    String? title,
  }) async {
    final appDir = await _requireAppDir();
    return rust_topic_threads.dbCreateTopicThread(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      title: title,
    );
  }

  Future<List<String>> listTopicThreadMessageIds(
    Uint8List key,
    String threadId,
  ) async {
    final appDir = await _resolveAppDirOrNull();
    if (appDir == null) return const <String>[];
    return rust_topic_threads.dbListTopicThreadMessageIds(
      appDir: appDir,
      key: key,
      threadId: threadId,
    );
  }

  Future<TopicThread> updateTopicThreadTitle(
    Uint8List key,
    String threadId, {
    String? title,
  }) async {
    final appDir = await _requireAppDir();
    return rust_topic_threads.dbUpdateTopicThreadTitle(
      appDir: appDir,
      key: key,
      threadId: threadId,
      title: title,
    );
  }

  Future<bool> deleteTopicThread(Uint8List key, String threadId) async {
    final appDir = await _requireAppDir();
    return rust_topic_threads.dbDeleteTopicThread(
      appDir: appDir,
      key: key,
      threadId: threadId,
    );
  }

  Future<List<String>> setTopicThreadMessageIds(
    Uint8List key,
    String threadId,
    List<String> messageIds,
  ) async {
    final appDir = await _requireAppDir();
    return rust_topic_threads.dbSetTopicThreadMessageIds(
      appDir: appDir,
      key: key,
      threadId: threadId,
      messageIds: messageIds,
    );
  }
}
