import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_ai_service.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

void main() {
  test('AI failure keeps local planning artifact persisted', () async {
    final now = DateTime(2026, 4, 29, 9);
    final backend = _PlanningBackend();
    final controller = SecretaryController(
      backend: backend,
      aiService: SecretaryAiService(promptClient: _ThrowingPromptClient()),
      aiRouteConfig: const SecretaryAiRouteConfig.byok(),
      planningEngine: RuleBasedPlanningEngine(nowLocal: () => now),
    );

    final plan = await controller.generateAndPersistPlan(
      Uint8List(32),
      [
        Todo(
          id: 't1',
          title: 'Submit app review',
          dueAtMs: platformIntFromInt(
            now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          ),
          status: 'open',
          createdAtMs: platformIntFromInt(1),
          updatedAtMs: platformIntFromInt(1),
        ),
      ],
      nowMs: now.millisecondsSinceEpoch,
    );

    expect(plan.route, 'local_rules');
    expect(plan.itemCount, 1);
    expect(backend.records.single.route, 'local_rules');
    expect(backend.records.single.state, 'active');
  });
}

final class _ThrowingPromptClient implements SecretaryAiPromptClient {
  @override
  Future<String> runByokSecretaryPrompt(
    Uint8List key, {
    required String prompt,
  }) async {
    throw StateError('AI unavailable');
  }

  @override
  Future<String> runCloudSecretaryPrompt(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String purpose,
  }) async {
    throw StateError('Cloud unavailable');
  }
}

final class _PlanningBackend implements SecretaryBackend {
  final List<PlanningOutputRecord> records = <PlanningOutputRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async {
    return records
        .where((record) => kind == null || record.kind == kind)
        .toList(growable: false);
  }

  @override
  Future<PlanningOutputRecord> upsertPlanningOutput(
    Uint8List key, {
    required String id,
    required String kind,
    required String title,
    required String body,
    required String itemsJson,
    String? sourceRefsJson,
    required String route,
    required String state,
    required int createdAtMs,
    required int updatedAtMs,
    int? expiresAtMs,
  }) async {
    final record = PlanningOutputRecord(
      id: id,
      kind: kind,
      title: title,
      body: body,
      itemsJson: itemsJson,
      sourceRefsJson: sourceRefsJson,
      route: route,
      state: state,
      createdAtMs: platformIntFromInt(createdAtMs),
      updatedAtMs: platformIntFromInt(updatedAtMs),
      expiresAtMs: expiresAtMs == null ? null : platformIntFromInt(expiresAtMs),
    );
    records
      ..removeWhere((existing) => existing.id == id)
      ..add(record);
    return record;
  }
}
