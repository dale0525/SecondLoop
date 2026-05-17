import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_ai_service.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

void main() {
  test('high-confidence local preference does not call BYOK or Cloud',
      () async {
    final backend = _MemoryBackend();
    final promptClient = _PromptClient();
    final controller = _controller(
      backend: backend,
      promptClient: promptClient,
      routeConfig: const SecretaryAiRouteConfig.byok(),
    );

    final proposal = await controller.persistMemoryProposalForMessage(
      Uint8List(32),
      const Message(
        id: 'm1',
        conversationId: 'loop_home',
        role: 'user',
        content: 'I prefer important work in the morning.',
        createdAtMs: 100,
        isMemory: true,
      ),
      nowMs: 110,
    );

    expect(proposal, isNotNull);
    expect(proposal!.body, contains('important work in the morning'));
    expect(promptClient.byokCalls, 0);
    expect(promptClient.cloudCalls, 0);
    expect(backend.createdProposalCount, 1);
  });

  test('weak preference hint uses BYOK enhancement when route is available',
      () async {
    final backend = _MemoryBackend();
    final promptClient = _PromptClient(
      responseJson: jsonEncode({
        'memory_proposal': {
          'kind': 'preference',
          'title': 'Afternoon meeting energy',
          'body': 'The user has low energy for meetings in the afternoon.',
          'confidence': 0.86,
        },
      }),
    );
    final controller = _controller(
      backend: backend,
      promptClient: promptClient,
      routeConfig: const SecretaryAiRouteConfig.byok(),
    );

    final proposal = await controller.persistMemoryProposalForMessage(
      Uint8List(32),
      const Message(
        id: 'm2',
        conversationId: 'loop_home',
        role: 'user',
        content: '下午开会我效率很差。',
        createdAtMs: 200,
        isMemory: true,
      ),
      nowMs: 210,
    );

    expect(proposal, isNotNull);
    expect(proposal!.title, 'Afternoon meeting energy');
    expect(proposal.body,
        'The user has low energy for meetings in the afternoon.');
    expect(promptClient.byokCalls, 1);
    expect(backend.createdProposalCount, 1);
    expect(backend.acceptedProposalIds, isEmpty);
  });

  test('AI failure keeps a local medium-confidence proposal', () async {
    final backend = _MemoryBackend();
    final promptClient = _PromptClient(throwByok: true);
    final controller = _controller(
      backend: backend,
      promptClient: promptClient,
      routeConfig: const SecretaryAiRouteConfig.byok(),
    );

    final proposal = await controller.persistMemoryProposalForMessage(
      Uint8List(32),
      const Message(
        id: 'm3',
        conversationId: 'loop_home',
        role: 'user',
        content: 'Actually, I no longer work with Alice.',
        createdAtMs: 300,
        isMemory: true,
      ),
      nowMs: 310,
    );

    expect(promptClient.byokCalls, 1);
    expect(proposal, isNotNull);
    expect(proposal!.body, contains('no longer work with Alice'));
    expect(backend.createdProposalCount, 1);
  });

  test('weak local hint stays quiet when AI enhancement fails', () async {
    final backend = _MemoryBackend();
    final promptClient = _PromptClient(throwByok: true);
    final controller = _controller(
      backend: backend,
      promptClient: promptClient,
      routeConfig: const SecretaryAiRouteConfig.byok(),
    );

    final proposal = await controller.persistMemoryProposalForMessage(
      Uint8List(32),
      const Message(
        id: 'm4',
        conversationId: 'loop_home',
        role: 'user',
        content: '下午开会我效率很差。',
        createdAtMs: 400,
        isMemory: true,
      ),
      nowMs: 410,
    );

    expect(promptClient.byokCalls, 1);
    expect(proposal, isNull);
    expect(backend.createdProposalCount, 0);
  });
}

SecretaryController _controller({
  required _MemoryBackend backend,
  required _PromptClient promptClient,
  required SecretaryAiRouteConfig routeConfig,
}) {
  return SecretaryController(
    backend: backend,
    aiService: SecretaryAiService(promptClient: promptClient),
    aiRouteConfig: routeConfig,
    planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
  );
}

final class _PromptClient implements SecretaryAiPromptClient {
  _PromptClient({
    this.responseJson = '{}',
    this.throwByok = false,
  });

  final String responseJson;
  final bool throwByok;
  int byokCalls = 0;
  int cloudCalls = 0;

  @override
  Future<String> runByokSecretaryPrompt(
    Uint8List key, {
    required String prompt,
  }) async {
    byokCalls += 1;
    if (throwByok) throw StateError('BYOK unavailable');
    return responseJson;
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
    cloudCalls += 1;
    return responseJson;
  }
}

final class _MemoryBackend implements SecretaryBackend {
  final Map<String, SecretaryMemoryProposalRecord> _proposals =
      <String, SecretaryMemoryProposalRecord>{};
  final List<String> acceptedProposalIds = <String>[];

  int get createdProposalCount => _proposals.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SecretaryMemoryProposalRecord> createSecretaryMemoryProposal(
    Uint8List key, {
    String? sourceMessageId,
    required String kind,
    required String title,
    required String body,
    required double confidence,
    String? sourceRefsJson,
    String? actionHint,
    required int nowMs,
  }) async {
    final record = SecretaryMemoryProposalRecord(
      id: 'proposal-${_proposals.length + 1}',
      sourceMessageId: sourceMessageId,
      kind: kind,
      title: title,
      body: body,
      confidence: confidence,
      state: 'pending',
      sourceRefsJson: sourceRefsJson,
      actionHint: actionHint,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    _proposals[record.id] = record;
    return record;
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    return _proposals.values
        .where((proposal) => state == null || proposal.state == state)
        .toList(growable: false);
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    acceptedProposalIds.add(proposalId);
    throw UnimplementedError('accept should not be called by routing tests');
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    return const <MemoryPageRecord>[];
  }
}
