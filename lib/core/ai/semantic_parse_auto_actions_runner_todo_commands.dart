part of 'semantic_parse_auto_actions_runner.dart';

final class _TodoCommandRunOutcome {
  const _TodoCommandRunOutcome({
    required this.handled,
    this.didMutate = false,
    this.didProcess = false,
  });

  final bool handled;
  final bool didMutate;
  final bool didProcess;
}

extension _SemanticParseAutoActionsRunnerTodoCommands
    on SemanticParseAutoActionsRunner {
  Future<_TodoCommandRunOutcome> _completeTodoCommandIfPresent({
    required String messageId,
    required int attemptId,
    required LocalSemanticParseResult localParsedResult,
    required AiSemanticDecision parsed,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    final command = localParsedResult.todoCommand;
    if (command == null || parsed.decision is! MessageActionNoneDecision) {
      return const _TodoCommandRunOutcome(handled: false);
    }

    const riskPolicy = SecretaryTodoCommandRiskPolicy();
    final risk = riskPolicy.classify(command);
    if (risk != SecretaryTodoCommandRisk.autoApply) {
      final appliedTagIds = await store.completeNoActionIfCurrentAttempt(
        messageId: messageId,
        expectedAttemptId: attemptId,
        pendingSuggestedTags: pendingSuggestedTags,
        autoApplySuggestedTags: autoApplySuggestedTags,
        suggestedTagConfidence: suggestedTagConfidence,
        nowMs: nowMs,
      );
      return _TodoCommandRunOutcome(
        handled: true,
        didMutate: appliedTagIds != null && appliedTagIds.isNotEmpty,
      );
    }

    if (!await _isStillRunningAttempt(
      messageId: messageId,
      attemptId: attemptId,
    )) {
      return const _TodoCommandRunOutcome(handled: true);
    }

    final commandStore = store;
    if (commandStore is! SemanticParseTodoCommandCompletingStore) {
      final appliedTagIds = await store.completeNoActionIfCurrentAttempt(
        messageId: messageId,
        expectedAttemptId: attemptId,
        pendingSuggestedTags: pendingSuggestedTags,
        autoApplySuggestedTags: autoApplySuggestedTags,
        suggestedTagConfidence: suggestedTagConfidence,
        nowMs: nowMs,
      );
      return _TodoCommandRunOutcome(
        handled: true,
        didMutate: appliedTagIds != null && appliedTagIds.isNotEmpty,
      );
    }

    final result =
        await (commandStore as SemanticParseTodoCommandCompletingStore)
            .completeTodoCommandIfCurrentAttempt(
      messageId: messageId,
      expectedAttemptId: attemptId,
      command: command,
      pendingSuggestedTags: pendingSuggestedTags,
      autoApplySuggestedTags: autoApplySuggestedTags,
      suggestedTagConfidence: suggestedTagConfidence,
      nowMs: nowMs,
    );
    if (result == null) {
      return const _TodoCommandRunOutcome(handled: true);
    }
    if (!result.applied) {
      return const _TodoCommandRunOutcome(handled: true);
    }

    await _recordSecretaryTodoMutation(
      messageId: messageId,
      toolName: secretaryToolNameForTodoCommand(command.kind),
      inputJson: jsonEncode(command.toJson()),
      outputJson: result.toAuditOutputJson(),
      nowMs: nowMs,
    );
    return const _TodoCommandRunOutcome(
      handled: true,
      didMutate: true,
      didProcess: true,
    );
  }
}
