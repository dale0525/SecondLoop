import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../backend/app_backend.dart';
import '../backend/native_app_dir.dart';
import 'package:secondloop/core/runtime_compat/api/detached_ask.dart'
    as rust_detached_ask;
import 'detached_ask_recovery_policy.dart';

const kAskAiDetachedJobPrefsKey = 'ask_ai_detached_job_v1';

final RegExp _kCloudDetachedRequestIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9:_-]{5,127}$',
);

const Duration _kDetachedSnapshotMaxAge = Duration(hours: 26);

enum DetachedAskSnapshotState {
  streamingConnected,
  streamingDisconnectedRecovering,
  completedRemotePendingSync,
}

String _snapshotStateToWire(DetachedAskSnapshotState state) => switch (state) {
      DetachedAskSnapshotState.streamingConnected => 'streaming_connected',
      DetachedAskSnapshotState.streamingDisconnectedRecovering =>
        'streaming_disconnected_recovering',
      DetachedAskSnapshotState.completedRemotePendingSync =>
        'completed_remote_pending_sync',
    };

DetachedAskSnapshotState _snapshotStateFromWire(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'streaming_disconnected_recovering':
      return DetachedAskSnapshotState.streamingDisconnectedRecovering;
    case 'completed_remote_pending_sync':
      return DetachedAskSnapshotState.completedRemotePendingSync;
    case 'streaming_connected':
    default:
      return DetachedAskSnapshotState.streamingConnected;
  }
}

final class DetachedAskSnapshot {
  const DetachedAskSnapshot({
    required this.requestId,
    required this.question,
    required this.conversationId,
    required this.gatewayBaseUrl,
    required this.createdAtMs,
    required this.state,
    required this.attemptCount,
    required this.lastPollAtMs,
  });

  final String? requestId;
  final String question;
  final String conversationId;
  final String? gatewayBaseUrl;
  final int createdAtMs;
  final DetachedAskSnapshotState state;
  final int attemptCount;
  final int? lastPollAtMs;
}

enum DetachedAskRecoverOutcomeKind {
  none,
  waitingForAuth,
  running,
  recovered,
  cleared,
  temporaryFailure,
}

final class DetachedAskRecoverOutcome {
  const DetachedAskRecoverOutcome({
    required this.kind,
    this.pollDelay,
    this.requestId,
    this.applied = false,
  });

  final DetachedAskRecoverOutcomeKind kind;
  final Duration? pollDelay;
  final String? requestId;
  final bool applied;
}

final class DetachedAskRecoveryService {
  static const String metricAskAiStreamStart = 'ask_ai_stream_start';
  static const String metricAskAiStreamDisconnect = 'ask_ai_stream_disconnect';
  static const String metricAskAiDetachedSnapshotPersisted =
      'ask_ai_detached_snapshot_persisted';
  static const String metricAskAiDetachedRecoverAttempt =
      'ask_ai_detached_recover_attempt';
  static const String metricAskAiDetachedRecoverSuccess =
      'ask_ai_detached_recover_success';
  static const String metricAskAiDetachedRecoverFailed =
      'ask_ai_detached_recover_failed';
  static const String metricAskAiDuplicateCompletionGuardHit =
      'ask_ai_duplicate_completion_guard_hit';

  static Future<void> persistSnapshot({
    required String? requestId,
    required String question,
    required String conversationId,
    String? gatewayBaseUrl,
    required DetachedAskSnapshotState state,
    int? createdAtMs,
    int? attemptCount,
    int? lastPollAtMs,
  }) async {
    final normalizedQuestion = question.trim();
    final normalizedConversationId = conversationId.trim();
    if (normalizedQuestion.isEmpty || normalizedConversationId.isEmpty) {
      return;
    }

    final normalizedRequestId = requestId?.trim();
    final normalizedGatewayBaseUrl = gatewayBaseUrl?.trim();

    final prefs = await SharedPreferences.getInstance();
    final payload = <String, Object?>{
      'request_id': (normalizedRequestId == null || normalizedRequestId.isEmpty)
          ? null
          : normalizedRequestId,
      'question': normalizedQuestion,
      'conversation_id': normalizedConversationId,
      'gateway_base_url':
          (normalizedGatewayBaseUrl == null || normalizedGatewayBaseUrl.isEmpty)
              ? null
              : normalizedGatewayBaseUrl,
      'created_at_ms': createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      'state': _snapshotStateToWire(state),
      'attempt_count': attemptCount,
      'last_poll_at_ms': lastPollAtMs,
    };

    await prefs.setString(kAskAiDetachedJobPrefsKey, jsonEncode(payload));
  }

  static Future<void> clearSnapshot({String? expectedRequestId}) async {
    final prefs = await SharedPreferences.getInstance();
    final expected = expectedRequestId?.trim() ?? '';
    if (expected.isEmpty) {
      await prefs.remove(kAskAiDetachedJobPrefsKey);
      return;
    }

    final snapshot = await readSnapshot();
    final current = snapshot?.requestId?.trim() ?? '';
    if (current == expected) {
      await prefs.remove(kAskAiDetachedJobPrefsKey);
    }
  }

  static Future<DetachedAskSnapshot?> readSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAskAiDetachedJobPrefsKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(kAskAiDetachedJobPrefsKey);
        return null;
      }

      int? parseInt(Object? value) {
        if (value is int) return value;
        if (value is double) return value.isFinite ? value.toInt() : null;
        if (value is String) return int.tryParse(value);
        return null;
      }

      final question = (decoded['question'] as String?)?.trim() ?? '';
      final conversationId =
          (decoded['conversation_id'] as String?)?.trim() ?? '';
      final createdAtMs = parseInt(decoded['created_at_ms']);
      if (question.isEmpty || conversationId.isEmpty || createdAtMs == null) {
        await prefs.remove(kAskAiDetachedJobPrefsKey);
        return null;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - createdAtMs > _kDetachedSnapshotMaxAge.inMilliseconds) {
        await prefs.remove(kAskAiDetachedJobPrefsKey);
        return null;
      }

      final requestId = (decoded['request_id'] as String?)?.trim();
      final gatewayBaseUrl = (decoded['gateway_base_url'] as String?)?.trim();
      final state = _snapshotStateFromWire(decoded['state'] as String?);
      final attemptCount = parseInt(decoded['attempt_count']) ?? 0;
      final lastPollAtMs = parseInt(decoded['last_poll_at_ms']);

      return DetachedAskSnapshot(
        requestId: (requestId == null || requestId.isEmpty) ? null : requestId,
        question: question,
        conversationId: conversationId,
        gatewayBaseUrl: (gatewayBaseUrl == null || gatewayBaseUrl.isEmpty)
            ? null
            : gatewayBaseUrl,
        createdAtMs: createdAtMs,
        state: state,
        attemptCount: attemptCount,
        lastPollAtMs: lastPollAtMs,
      );
    } catch (_) {
      await prefs.remove(kAskAiDetachedJobPrefsKey);
      return null;
    }
  }

  static Future<void> ackCloudDetachedJob({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) async {
    if (!_kCloudDetachedRequestIdPattern.hasMatch(requestId.trim())) return;

    final base = gatewayBaseUrl.trim();
    final token = idToken.trim();
    if (base.isEmpty || token.isEmpty) return;

    final uri = _buildAckUri(base, requestId.trim());
    if (uri == null) return;

    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
    ];

    for (final delay in retryDelays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      try {
        final req =
            await client.postUrl(uri).timeout(const Duration(seconds: 6));
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final resp = await req.close().timeout(const Duration(seconds: 6));
        await resp.drain<void>().timeout(const Duration(seconds: 6));

        if ((resp.statusCode >= 200 && resp.statusCode < 300) ||
            resp.statusCode == 404) {
          return;
        }
        if (resp.statusCode != 409) {
          return;
        }
      } catch (_) {
        // Best-effort only.
      } finally {
        client.close(force: true);
      }
    }
  }

  static Future<void> cancelCloudDetachedJob({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) async {
    final base = gatewayBaseUrl.trim();
    final token = idToken.trim();
    final rid = requestId.trim();
    if (base.isEmpty || token.isEmpty || rid.isEmpty) return;

    final client = HttpClient();
    try {
      final uri = Uri.parse(base).resolve('/v1/chat/jobs/$rid/cancel');
      final req =
          await client.postUrl(uri).timeout(const Duration(seconds: 12));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode('{}'));
      final resp = await req.close().timeout(const Duration(seconds: 45));
      await utf8.decodeStream(resp).timeout(const Duration(seconds: 45));
    } catch (_) {
      // Best-effort only.
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> fetchCloudDetachedJobStatus({
    required String gatewayBaseUrl,
    required String idToken,
    required String requestId,
  }) async {
    final base = gatewayBaseUrl.trim();
    final token = idToken.trim();
    final rid = requestId.trim();
    if (base.isEmpty || token.isEmpty || rid.isEmpty) return null;

    final client = HttpClient();
    try {
      final uri = Uri.parse(base).resolve('/v1/chat/jobs/$rid');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final resp = await req.close().timeout(const Duration(seconds: 45));
      final text =
          await utf8.decodeStream(resp).timeout(const Duration(seconds: 45));
      if (resp.statusCode == 404) {
        return <String, dynamic>{'status': 'not_found'};
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> applyCompletionOnceViaEventMarker({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String requestId,
    required String conversationId,
    required String question,
    required String answer,
    String? citationsJson,
    String? gatewayBaseUrl,
  }) async {
    final rid = requestId.trim();
    final cid = conversationId.trim();
    final q = question.trim();
    final a = answer.trim();
    if (rid.isEmpty || cid.isEmpty || q.isEmpty || a.isEmpty) {
      return false;
    }

    try {
      final appDir = await getNativeAppDir();
      return await rust_detached_ask.dbApplyDetachedAskCompletionOnce(
        appDir: appDir,
        key: sessionKey,
        requestId: rid,
        conversationId: cid,
        question: q,
        answer: a,
        citationsJson: citationsJson,
      );
    } catch (_) {
      return _applyCompletionViaBackendRecovery(
        backend: backend,
        sessionKey: sessionKey,
        requestId: rid,
        conversationId: cid,
        question: q,
        answer: a,
        citationsJson: citationsJson,
      );
    }
  }

  static Future<bool> _applyCompletionViaBackendRecovery({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String requestId,
    required String conversationId,
    required String question,
    required String answer,
    String? citationsJson,
  }) async {
    if (backend is! DetachedAskCompletionRecoveryBackend) {
      return false;
    }
    final recoveryBackend = backend as DetachedAskCompletionRecoveryBackend;
    return recoveryBackend.applyDetachedAskCompletionOnce(
      sessionKey,
      requestId: requestId,
      conversationId: conversationId,
      question: question,
      answer: answer,
      citationsJson: citationsJson,
    );
  }

  static Future<void> trackMetric({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String metric,
    required String conversationId,
    String? requestId,
    String? detail,
    int? attemptCount,
    bool dedupeByRequestId = false,
  }) async {
    final normalizedMetric = metric.trim();
    final normalizedConversationId = conversationId.trim();
    if (normalizedMetric.isEmpty || normalizedConversationId.isEmpty) {
      return;
    }

    final rid = (requestId ?? '').trim();
    final ridToken = _sanitizeMetricToken(rid.isEmpty ? 'none' : rid);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final id = dedupeByRequestId && rid.isNotEmpty
        ? 'ask_ai_metric:$normalizedMetric:$ridToken'
        : 'ask_ai_metric:$normalizedMetric:$ridToken:$nowMs';
    final titlePayload = <String, Object?>{
      'metric': normalizedMetric,
      'request_id': rid.isEmpty ? null : rid,
      'detail': detail?.trim().isEmpty ?? true ? null : detail!.trim(),
      'attempt_count': attemptCount,
      'at_ms': nowMs,
    };

    try {
      await backend.upsertEvent(
        sessionKey,
        id: id,
        title: 'ask_ai_metric_v1:${jsonEncode(titlePayload)}',
        startAtMs: nowMs,
        endAtMs: nowMs + 1,
        tz: 'UTC',
        sourceEntryId: normalizedConversationId,
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  static Future<DetachedAskRecoverOutcome> recoverIfNeeded({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String? idToken,
    required String defaultGatewayBaseUrl,
  }) async {
    final snapshot = await readSnapshot();
    if (snapshot == null) {
      return const DetachedAskRecoverOutcome(
          kind: DetachedAskRecoverOutcomeKind.none);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nextAttempt = snapshot.attemptCount + 1;
    final rid = snapshot.requestId?.trim() ?? '';
    if (rid.isEmpty || !_kCloudDetachedRequestIdPattern.hasMatch(rid)) {
      await _persistSnapshotProgress(
        snapshot,
        state: DetachedAskSnapshotState.streamingDisconnectedRecovering,
        requestId: snapshot.requestId,
        attemptCount: nextAttempt,
        lastPollAtMs: nowMs,
      );
      return const DetachedAskRecoverOutcome(
        kind: DetachedAskRecoverOutcomeKind.temporaryFailure,
      );
    }

    final token = (idToken ?? '').trim();
    if (token.isEmpty) {
      await _persistSnapshotProgress(
        snapshot,
        state: DetachedAskSnapshotState.streamingDisconnectedRecovering,
        requestId: rid,
        attemptCount: nextAttempt,
        lastPollAtMs: nowMs,
      );
      return const DetachedAskRecoverOutcome(
        kind: DetachedAskRecoverOutcomeKind.waitingForAuth,
      );
    }

    final gatewayBaseUrl = (snapshot.gatewayBaseUrl?.trim().isNotEmpty ?? false)
        ? snapshot.gatewayBaseUrl!.trim()
        : defaultGatewayBaseUrl.trim();
    if (gatewayBaseUrl.isEmpty) {
      await _persistSnapshotProgress(
        snapshot,
        state: DetachedAskSnapshotState.streamingDisconnectedRecovering,
        requestId: rid,
        attemptCount: nextAttempt,
        lastPollAtMs: nowMs,
      );
      return const DetachedAskRecoverOutcome(
        kind: DetachedAskRecoverOutcomeKind.waitingForAuth,
      );
    }

    await trackMetric(
      backend: backend,
      sessionKey: sessionKey,
      metric: metricAskAiDetachedRecoverAttempt,
      conversationId: snapshot.conversationId,
      requestId: rid,
      attemptCount: nextAttempt,
    );

    final status = await fetchCloudDetachedJobStatus(
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: token,
      requestId: rid,
    );
    if (status == null) {
      await _persistSnapshotProgress(
        snapshot,
        state: DetachedAskSnapshotState.streamingDisconnectedRecovering,
        requestId: rid,
        attemptCount: nextAttempt,
        lastPollAtMs: nowMs,
      );
      await trackMetric(
        backend: backend,
        sessionKey: sessionKey,
        metric: metricAskAiDetachedRecoverFailed,
        conversationId: snapshot.conversationId,
        requestId: rid,
        detail: 'status_fetch_failed',
        attemptCount: nextAttempt,
      );
      return const DetachedAskRecoverOutcome(
        kind: DetachedAskRecoverOutcomeKind.temporaryFailure,
      );
    }

    final state = (status['status'] as String?)?.trim().toLowerCase() ?? '';
    if (state == 'running' || state == 'cancel_requested') {
      await _persistSnapshotProgress(
        snapshot,
        state: DetachedAskSnapshotState.streamingDisconnectedRecovering,
        requestId: rid,
        attemptCount: nextAttempt,
        lastPollAtMs: nowMs,
      );
      return DetachedAskRecoverOutcome(
        kind: DetachedAskRecoverOutcomeKind.running,
        pollDelay: detachedAskRecoveryPollDelay(
          nowMs: nowMs,
          createdAtMs: snapshot.createdAtMs,
        ),
        requestId: rid,
      );
    }

    if (state == 'completed') {
      final resultText = (status['result_text'] as String?)?.trim() ?? '';
      if (resultText.isEmpty) {
        await trackMetric(
          backend: backend,
          sessionKey: sessionKey,
          metric: metricAskAiDetachedRecoverFailed,
          conversationId: snapshot.conversationId,
          requestId: rid,
          detail: 'completed_without_result',
          attemptCount: nextAttempt,
        );
        await clearSnapshot(expectedRequestId: rid);
        return DetachedAskRecoverOutcome(
          kind: DetachedAskRecoverOutcomeKind.cleared,
          requestId: rid,
        );
      }

      await _persistSnapshotProgress(
        snapshot,
        state: DetachedAskSnapshotState.completedRemotePendingSync,
        requestId: rid,
        attemptCount: nextAttempt,
        lastPollAtMs: nowMs,
      );
      final applied = await applyCompletionOnceViaEventMarker(
        backend: backend,
        sessionKey: sessionKey,
        requestId: rid,
        conversationId: snapshot.conversationId,
        question: snapshot.question,
        answer: resultText,
        gatewayBaseUrl: gatewayBaseUrl,
      );
      if (!applied) {
        await trackMetric(
          backend: backend,
          sessionKey: sessionKey,
          metric: metricAskAiDuplicateCompletionGuardHit,
          conversationId: snapshot.conversationId,
          requestId: rid,
          detail: 'event_marker_exists',
          attemptCount: nextAttempt,
          dedupeByRequestId: true,
        );
      }
      await trackMetric(
        backend: backend,
        sessionKey: sessionKey,
        metric: metricAskAiDetachedRecoverSuccess,
        conversationId: snapshot.conversationId,
        requestId: rid,
        detail: applied ? 'applied' : 'already_applied',
        attemptCount: nextAttempt,
      );

      await ackCloudDetachedJob(
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: token,
        requestId: rid,
      );
      await clearSnapshot(expectedRequestId: rid);

      return DetachedAskRecoverOutcome(
        kind: DetachedAskRecoverOutcomeKind.recovered,
        requestId: rid,
        applied: applied,
      );
    }

    await trackMetric(
      backend: backend,
      sessionKey: sessionKey,
      metric: metricAskAiDetachedRecoverFailed,
      conversationId: snapshot.conversationId,
      requestId: rid,
      detail: 'terminal_state:$state',
      attemptCount: nextAttempt,
    );
    await clearSnapshot(expectedRequestId: rid);
    return DetachedAskRecoverOutcome(
      kind: DetachedAskRecoverOutcomeKind.cleared,
      requestId: rid,
    );
  }

  static Uri? _buildAckUri(String gatewayBaseUrl, String requestId) {
    final normalizedBase = gatewayBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    if (normalizedBase.isEmpty || requestId.isEmpty) return null;

    try {
      return Uri.parse('$normalizedBase/v1/chat/jobs/$requestId/ack');
    } catch (_) {
      return null;
    }
  }

  static String _sanitizeMetricToken(String raw) {
    final compact = raw.replaceAll(RegExp(r'[^A-Za-z0-9:_-]'), '_');
    if (compact.isEmpty) return 'na';
    if (compact.length <= 48) return compact;
    return compact.substring(0, 48);
  }

  static Future<void> _persistSnapshotProgress(
    DetachedAskSnapshot snapshot, {
    required DetachedAskSnapshotState state,
    required String? requestId,
    required int attemptCount,
    required int lastPollAtMs,
  }) {
    return persistSnapshot(
      requestId: requestId,
      question: snapshot.question,
      conversationId: snapshot.conversationId,
      gatewayBaseUrl: snapshot.gatewayBaseUrl,
      state: state,
      createdAtMs: snapshot.createdAtMs,
      attemptCount: attemptCount,
      lastPollAtMs: lastPollAtMs,
    );
  }
}
