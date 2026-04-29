import 'dart:convert';

import 'secretary_models.dart';

final class SecretaryAiPrompts {
  const SecretaryAiPrompts._();

  static String planningEnhancement({
    required SecretaryPlan localPlan,
    required String localeTag,
  }) {
    return jsonEncode({
      'purpose': 'secretary',
      'task': 'enhance_planning_draft',
      'locale': localeTag,
      'rules': [
        'Return JSON only.',
        'Do not create, update, delete, reorder, or complete todos.',
        'Do not create reminders or write long-term memory.',
        'Only improve explanations and propose missing next actions.',
      ],
      'response_schema': {
        'planning_explanation': 'string',
        'missing_next_actions': [
          {'todo_id': 'string', 'suggestion': 'string'},
        ],
      },
      'local_plan': _planToJson(localPlan),
    });
  }

  static String memoryProposalEnhancement({
    required SecretaryMemoryProposal proposal,
  }) {
    return jsonEncode({
      'purpose': 'secretary',
      'task': 'enhance_memory_proposal',
      'rules': [
        'Return JSON only.',
        'Do not write long-term memory.',
        'Only rewrite a pending proposal for later user review.',
        'List superseded memory ids as candidates only.',
      ],
      'response_schema': {
        'memory_proposal': {
          'kind': 'string',
          'title': 'string',
          'body': 'string',
          'confidence': 'number',
          'supersedes_candidate_ids': ['string'],
        },
      },
      'proposal': {
        'id': proposal.id,
        'source_message_id': proposal.sourceMessageId,
        'kind': proposal.kind,
        'title': proposal.title,
        'body': proposal.body,
        'confidence': proposal.confidence,
        'action_hint': proposal.actionHint,
      },
    });
  }

  static Map<String, Object?> _planToJson(SecretaryPlan plan) {
    return {
      'id': plan.id,
      'title': plan.title,
      'route': plan.route,
      'generated_at_ms': plan.generatedAtMs,
      'sections': {
        'focus': _itemsToJson(plan.sections.focus),
        'due_soon': _itemsToJson(plan.sections.dueSoon),
        'needs_decision': _itemsToJson(plan.sections.needsDecision),
        'missing_next_action': _itemsToJson(plan.sections.missingNextAction),
      },
    };
  }

  static List<Map<String, Object?>> _itemsToJson(
    List<SecretaryPlanItem> items,
  ) {
    return [
      for (final item in items)
        {
          'id': item.id,
          'todo_id': item.todoId,
          'title': item.title,
          'reason': item.reason,
          'due_at_ms': item.dueAtMs,
          'requires_confirmation': item.requiresConfirmation,
        },
    ];
  }
}
