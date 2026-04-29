import '../../src/rust/db.dart';
import '../../src/rust/platform_int.dart';
import 'memory_proposal_detector.dart';
import 'rule_based_planning_engine.dart';
import 'secretary_models.dart';

class SecretaryController {
  SecretaryController({
    MemoryProposalDetector detector = const MemoryProposalDetector(),
    required RuleBasedPlanningEngine planningEngine,
  })  : _detector = detector,
        _planningEngine = planningEngine;

  final MemoryProposalDetector _detector;
  final RuleBasedPlanningEngine _planningEngine;
  final Set<String> _acceptedProposalSourceIds = <String>{};
  final Set<String> _dismissedProposalSourceIds = <String>{};
  final Set<String> _dismissedPlanIds = <String>{};

  List<SecretaryMemoryProposal> pendingMemoryProposalsForMessages(
    List<Message> messages,
  ) {
    final proposals = <SecretaryMemoryProposal>[];
    for (final message in messages) {
      if (message.role != 'user') continue;
      if (_acceptedProposalSourceIds.contains(message.id)) continue;
      if (_dismissedProposalSourceIds.contains(message.id)) continue;
      final proposal = _detector.detect(
        messageId: message.id,
        text: message.content,
        createdAtMs: platformIntToInt(message.createdAtMs),
      );
      if (proposal != null) proposals.add(proposal);
    }
    return proposals;
  }

  SecretaryMemoryPage acceptMemoryProposal(SecretaryMemoryProposal proposal) {
    _acceptedProposalSourceIds.add(proposal.sourceMessageId);
    return SecretaryMemoryPage(
      id: 'memory-${proposal.sourceMessageId}',
      title: proposal.title,
      body: proposal.body,
      state: SecretaryMemoryState.active,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      kind: proposal.kind,
      sourceMessageId: proposal.sourceMessageId,
    );
  }

  void dismissMemoryProposal(SecretaryMemoryProposal proposal) {
    _dismissedProposalSourceIds.add(proposal.sourceMessageId);
  }

  SecretaryPlan generatePlan(List<Todo> todos) {
    final plan = _planningEngine.generateDailyPlan(todos);
    if (_dismissedPlanIds.contains(plan.id)) {
      return const SecretaryPlan(
        id: 'dismissed',
        title: 'Daily plan',
        generatedAtMs: 0,
        route: 'local_rules',
        sections: SecretaryPlanSections.empty(),
      );
    }
    return plan;
  }

  void dismissPlan(SecretaryPlan plan) {
    _dismissedPlanIds.add(plan.id);
  }
}
