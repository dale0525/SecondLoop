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
  testWidgets('no-route gate cancels due pending/running semantic jobs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _FakeSemanticParseGateBackend(
      dueJobs: <SemanticParseJob>[
        _job(messageId: 'm1', status: 'pending'),
        _job(messageId: 'm2', status: 'running'),
        _job(messageId: 'm3', status: 'succeeded'),
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

    await tester.pump(const Duration(seconds: 3));

    expect(backend.canceledMessageIds, containsAll(<String>['m1', 'm2']));
    expect(backend.canceledMessageIds, isNot(contains('m3')));
  });
}

SemanticParseJob _job({
  required String messageId,
  required String status,
}) {
  return SemanticParseJob(
    messageId: messageId,
    status: status,
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
    required this.dueJobs,
  }) : super(appDirProvider: () async => '/tmp/secondloop-test');

  final List<SemanticParseJob> dueJobs;
  final List<String> canceledMessageIds = <String>[];

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    return const <LlmProfile>[];
  }

  @override
  Future<List<SemanticParseJob>> listDueSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    return dueJobs.take(limit).toList(growable: false);
  }

  @override
  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    canceledMessageIds.add(messageId);
  }
}
