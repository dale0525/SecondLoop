import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

void main() {
  test('native backend forwards secretary proposal and planning calls',
      () async {
    const appDir = '/tmp/secondloop-secretary-backend-test';
    final key = Uint8List(32);
    final calls = <String>[];
    String? listState;
    String? planningKind;

    final backend = NativeAppBackend(
      appDirProvider: () async => appDir,
      recoverInterruptedExternalImportBatchesOnInit: false,
      dbCreateSecretaryMemoryProposal: ({
        required appDir,
        required key,
        sourceMessageId,
        required kind,
        required title,
        required body,
        required confidence,
        sourceRefsJson,
        actionHint,
        required nowMs,
      }) async {
        calls.add('create:$appDir:$kind:$title:${platformIntToInt(nowMs)}');
        return _proposal(
          id: 'p1',
          sourceMessageId: sourceMessageId,
          kind: kind,
          title: title,
          body: body,
          confidence: confidence,
          state: 'pending',
          nowMs: platformIntToInt(nowMs),
        );
      },
      dbListSecretaryMemoryProposals: ({
        required appDir,
        required key,
        state,
      }) async {
        listState = state;
        return [_proposal(id: 'p1', nowMs: 10)];
      },
      dbAcceptSecretaryMemoryProposal: ({
        required appDir,
        required key,
        required proposalId,
        required nowMs,
      }) async {
        calls.add('accept:$proposalId:${platformIntToInt(nowMs)}');
        return _memoryPage(id: 'm1', state: 'active', nowMs: 20);
      },
      dbDismissSecretaryMemoryProposal: ({
        required appDir,
        required key,
        required proposalId,
        required nowMs,
      }) async {
        calls.add('dismiss:$proposalId:${platformIntToInt(nowMs)}');
        return _proposal(id: proposalId, state: 'dismissed', nowMs: 30);
      },
      dbUpsertPlanningOutput: ({
        required appDir,
        required key,
        required id,
        required kind,
        required title,
        required body,
        required itemsJson,
        sourceRefsJson,
        required route,
        required state,
        required createdAtMs,
        required updatedAtMs,
        expiresAtMs,
      }) async {
        calls.add('plan:$id:$kind:$state');
        return _planningOutput(id: id, kind: kind, state: state, nowMs: 40);
      },
      dbListPlanningOutputs: ({
        required appDir,
        required key,
        kind,
        required nowMs,
        required includeExpired,
      }) async {
        planningKind = kind;
        return [_planningOutput(id: 'plan1', kind: kind ?? 'daily_plan')];
      },
    );

    expect(backend, isA<SecretaryBackend>());

    final created = await backend.createSecretaryMemoryProposal(
      key,
      sourceMessageId: 'message1',
      kind: 'preference',
      title: 'Morning meetings',
      body: 'I prefer morning meetings.',
      confidence: 0.92,
      sourceRefsJson: '{"message_ids":["message1"]}',
      actionHint: 'propose',
      nowMs: 100,
    );
    expect(created.state, 'pending');

    final proposals =
        await backend.listSecretaryMemoryProposals(key, state: 'pending');
    expect(proposals.single.id, 'p1');
    expect(listState, 'pending');

    final page = await backend.acceptSecretaryMemoryProposal(
      key,
      proposalId: 'p1',
      nowMs: 120,
    );
    expect(page.state, 'active');

    final dismissed = await backend.dismissSecretaryMemoryProposal(
      key,
      proposalId: 'p1',
      nowMs: 130,
    );
    expect(dismissed.state, 'dismissed');

    final output = await backend.upsertPlanningOutput(
      key,
      id: 'plan1',
      kind: 'daily_plan',
      title: 'Daily plan',
      body: 'Focus on two items.',
      itemsJson: '[]',
      sourceRefsJson: null,
      route: 'local_rules',
      state: 'active',
      createdAtMs: 140,
      updatedAtMs: 150,
      expiresAtMs: 160,
    );
    expect(output.kind, 'daily_plan');

    final outputs = await backend.listPlanningOutputs(
      key,
      kind: 'daily_plan',
      nowMs: 170,
      includeExpired: false,
    );
    expect(outputs.single.id, 'plan1');
    expect(planningKind, 'daily_plan');

    expect(
        calls,
        containsAll(<String>[
          'create:$appDir:preference:Morning meetings:100',
          'accept:p1:120',
          'dismiss:p1:130',
          'plan:plan1:daily_plan:active',
        ]));
  });
}

SecretaryMemoryProposalRecord _proposal({
  required String id,
  String? sourceMessageId,
  String kind = 'fact',
  String title = 'Remember this',
  String body = 'Remember this body',
  double confidence = 0.8,
  String state = 'pending',
  int nowMs = 10,
}) {
  return SecretaryMemoryProposalRecord(
    id: id,
    sourceMessageId: sourceMessageId,
    kind: kind,
    title: title,
    body: body,
    confidence: confidence,
    state: state,
    sourceRefsJson: null,
    actionHint: 'propose',
    createdAtMs: platformIntFromInt(nowMs),
    updatedAtMs: platformIntFromInt(nowMs),
    acceptedAtMs: state == 'accepted' ? platformIntFromInt(nowMs) : null,
    dismissedAtMs: state == 'dismissed' ? platformIntFromInt(nowMs) : null,
  );
}

MemoryPageRecord _memoryPage({
  required String id,
  required String state,
  int nowMs = 20,
}) {
  return MemoryPageRecord(
    pageId: id,
    pageType: 'memory',
    state: state,
    sourceCount: platformIntFromInt(1),
    title: 'Morning meetings',
    summary: 'I prefer morning meetings.',
    body: 'I prefer morning meetings.',
    primaryEvidenceJson: '[]',
    sourceDocumentIdsJson: '[]',
    confidenceLevel: 0.9,
    humanCorrected: false,
    createdAtMs: platformIntFromInt(nowMs),
    updatedAtMs: platformIntFromInt(nowMs),
  );
}

PlanningOutputRecord _planningOutput({
  required String id,
  String kind = 'daily_plan',
  String state = 'active',
  int nowMs = 40,
}) {
  return PlanningOutputRecord(
    id: id,
    kind: kind,
    title: 'Daily plan',
    body: 'Focus on two items.',
    itemsJson: '[]',
    sourceRefsJson: null,
    route: 'local_rules',
    state: state,
    createdAtMs: platformIntFromInt(nowMs),
    updatedAtMs: platformIntFromInt(nowMs),
    expiresAtMs: null,
    dismissedAtMs: state == 'dismissed' ? platformIntFromInt(nowMs) : null,
  );
}
