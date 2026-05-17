import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/secretary/internal_tool_registry.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

void main() {
  test('records a secretary run with auditable tool calls', () async {
    final backend = _AuditBackend();
    final controller = SecretaryController(
      backend: backend,
      planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
    );

    final trail = await controller.recordSecretaryRun(
      Uint8List(32),
      triggerKind: 'manual',
      route: 'local_rules',
      status: 'succeeded',
      inputSummary: 'Generate today plan',
      outputSummary: 'Created one planning draft',
      nowMs: 1000,
      toolCalls: const [
        SecretaryToolCallDraft(
          toolName: 'plan.generate',
          status: 'succeeded',
          requiresConfirmation: false,
          inputJson: '{"kind":"daily_plan"}',
          outputJson: '{"planning_output_id":"plan-1"}',
        ),
      ],
    );

    expect(trail.run.triggerKind, 'manual');
    expect(trail.run.route, 'local_rules');
    expect(trail.run.inputSummary, 'Generate today plan');
    expect(trail.run.outputSummary, 'Created one planning draft');
    expect(trail.toolCalls.single.runId, trail.run.id);
    expect(trail.toolCalls.single.toolName, 'plan.generate');
    expect(trail.toolCalls.single.requiresConfirmation, isFalse);
    expect(trail.toolCalls.single.inputJson, contains('daily_plan'));
    expect(backend.createdRuns.single.id, trail.run.id);
  });

  test('internal registry declares bounded secretary tools', () {
    final registry = SecretaryInternalToolRegistry.defaults();

    expect(registry.require('memory.search').scope, 'read');
    expect(registry.require('memory.update').requiresConfirmation, isTrue);
    expect(registry.require('todo.create').scope, 'write');
    expect(registry.require('reminder.suggest').requiresConfirmation, isTrue);
    expect(registry.tryGet('web.genericBrowser'), isNull);
  });
}

final class _AuditBackend implements SecretaryBackend {
  final List<SecretaryRunRecord> createdRuns = <SecretaryRunRecord>[];
  final List<SecretaryToolCallRecord> createdCalls =
      <SecretaryToolCallRecord>[];

  @override
  Future<SecretaryRunRecord> createSecretaryRun(
    Uint8List key, {
    required String triggerKind,
    required String route,
    required String status,
    String? inputSummary,
    String? outputSummary,
    String? error,
    required int nowMs,
  }) async {
    final record = SecretaryRunRecord(
      id: 'run-${createdRuns.length + 1}',
      triggerKind: triggerKind,
      route: route,
      status: status,
      inputSummary: inputSummary,
      outputSummary: outputSummary,
      error: error,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    createdRuns.add(record);
    return record;
  }

  @override
  Future<SecretaryToolCallRecord> createSecretaryToolCall(
    Uint8List key, {
    required String runId,
    required String toolName,
    required String status,
    required bool requiresConfirmation,
    String? inputJson,
    String? outputJson,
    required int nowMs,
  }) async {
    final record = SecretaryToolCallRecord(
      id: 'call-${createdCalls.length + 1}',
      runId: runId,
      toolName: toolName,
      status: status,
      requiresConfirmation: requiresConfirmation,
      inputJson: inputJson,
      outputJson: outputJson,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    createdCalls.add(record);
    return record;
  }

  @override
  Future<List<SecretaryToolCallRecord>> listSecretaryToolCallsForRun(
    Uint8List key, {
    required String runId,
  }) async {
    return createdCalls
        .where((record) => record.runId == runId)
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
