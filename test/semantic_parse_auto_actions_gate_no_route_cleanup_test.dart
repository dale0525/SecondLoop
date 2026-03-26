import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_gate.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  testWidgets(
      'no-route gate recovers running jobs before canceling due semantic jobs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _FakeSemanticParseGateBackend(
      dueJobs: <SemanticParseJob>[
        _job(messageId: 'm1', status: 'pending'),
        _job(messageId: 'm3', status: 'succeeded'),
      ],
      recoveredRunningJobs: <SemanticParseJob>[
        _job(messageId: 'm2', status: 'pending'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const SemanticParseAutoActionsGate(
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(backend.canceledMessageIds, isEmpty);
    expect(backend.requeueCalls, 0);

    await tester.pump(const Duration(seconds: 3));

    expect(backend.requeueCalls, 1);
    expect(backend.canceledMessageIds, containsAll(<String>['m1', 'm2']));
    expect(backend.canceledMessageIds, isNot(contains('m3')));
    expect(backend.releaseCalls, greaterThanOrEqualTo(1));
  });
}

SemanticParseJob _job({
  required String messageId,
  required String status,
}) {
  return SemanticParseJob(
    messageId: messageId,
    status: status,
    attemptId: PlatformInt64Util.from(0),
    attempts: PlatformInt64Util.from(0),
    nextRetryAtMs: null,
    lastError: null,
    appliedActionKind: null,
    appliedTodoId: null,
    appliedTodoTitle: null,
    appliedPrevTodoStatus: null,
    suggestedTags: null,
    suggestedTagConfidence: null,
    tagSuggestionState: null,
    appliedTagIds: null,
    undoneAtMs: null,
    createdAtMs: PlatformInt64Util.from(0),
    updatedAtMs: PlatformInt64Util.from(0),
  );
}

final class _FakeSemanticParseGateBackend extends NativeAppBackend {
  _FakeSemanticParseGateBackend({
    required List<SemanticParseJob> dueJobs,
    required List<SemanticParseJob> recoveredRunningJobs,
  })  : _dueJobs = List<SemanticParseJob>.from(dueJobs),
        _recoveredRunningJobs =
            List<SemanticParseJob>.from(recoveredRunningJobs),
        super(appDirProvider: () async => '/tmp/secondloop-test');

  final List<SemanticParseJob> _dueJobs;
  final List<SemanticParseJob> _recoveredRunningJobs;
  final List<String> canceledMessageIds = <String>[];
  int requeueCalls = 0;
  int releaseCalls = 0;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    return const <LlmProfile>[];
  }

  @override
  Future<int> requeueRunningSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
  }) async {
    requeueCalls += 1;
    _dueJobs.insertAll(0, _recoveredRunningJobs);
    final count = _recoveredRunningJobs.length;
    _recoveredRunningJobs.clear();
    return count;
  }

  @override
  Future<List<SemanticParseJob>> listDueSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    return _dueJobs.take(limit).toList(growable: false);
  }

  @override
  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    canceledMessageIds.add(messageId);
  }

  @override
  Future<bool> releaseLocalEmbeddingModelIfIdle(
    Uint8List key, {
    int maxIdleMs = 180000,
  }) async {
    releaseCalls += 1;
    return false;
  }
}
