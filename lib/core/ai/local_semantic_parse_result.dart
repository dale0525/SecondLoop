import '../../features/actions/todo/message_action_resolver.dart';

enum LocalSemanticParseKind { none, create, followup }

enum SemanticResolver { local, llm, hybrid }

final class LocalSemanticParseDiagnostics {
  const LocalSemanticParseDiagnostics({
    this.localIntent = 'none',
  });

  final String localIntent;
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
  final LocalSemanticParseDiagnostics diagnostics;
}
