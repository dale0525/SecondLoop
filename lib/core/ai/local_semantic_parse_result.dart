import '../../features/actions/todo/message_action_resolver.dart';
import '../secretary/todo_command_models.dart';

enum LocalSemanticParseKind { none, create, followup }

enum SemanticResolver { local, llm, hybrid }

final class LocalSemanticParseDiagnostics {
  const LocalSemanticParseDiagnostics({
    this.localIntent = 'none',
    this.hasExplicitStatusUpdate = false,
    this.hasDueSignal = false,
    this.temporalNeedsEnhancement = false,
    this.semanticNeedsEnhancement = false,
    this.looksLikeFollowupEdit = false,
    this.todoCommandIntent = 'none',
    this.todoCommandNeedsEnhancement = false,
    this.todoCommandAmbiguous = false,
  });

  final String localIntent;
  final bool hasExplicitStatusUpdate;
  final bool hasDueSignal;
  final bool temporalNeedsEnhancement;
  final bool semanticNeedsEnhancement;
  final bool looksLikeFollowupEdit;
  final String todoCommandIntent;
  final bool todoCommandNeedsEnhancement;
  final bool todoCommandAmbiguous;
}

final class LocalSemanticParseResult {
  const LocalSemanticParseResult({
    required this.kind,
    required this.confidence,
    required this.resolver,
    this.title,
    this.status,
    this.todoId,
    this.dueAtLocal,
    this.recurrenceRule,
    this.taskType,
    this.suggestedTags = const <String>[],
    this.tagConfidence = 0,
    this.todoCommand,
    this.diagnostics = const LocalSemanticParseDiagnostics(),
  });

  final LocalSemanticParseKind kind;
  final double confidence;
  final SemanticResolver resolver;
  final String? title;
  final String? status;
  final String? todoId;
  final DateTime? dueAtLocal;
  final MessageActionRecurrenceRule? recurrenceRule;
  final String? taskType;
  final List<String> suggestedTags;
  final double tagConfidence;
  final SecretaryTodoCommand? todoCommand;
  final LocalSemanticParseDiagnostics diagnostics;
}
