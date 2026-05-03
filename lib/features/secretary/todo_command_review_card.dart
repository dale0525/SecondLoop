import 'package:flutter/material.dart';

import '../../core/secretary/todo_command_models.dart';
import '../../core/secretary/todo_command_risk_policy.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

class ChatSecretaryTodoCommandCard extends StatelessWidget {
  const ChatSecretaryTodoCommandCard({
    required this.command,
    required this.onApply,
    required this.onReview,
    required this.onIgnore,
    this.onEdit,
    super.key,
  });

  final SecretaryTodoCommand command;
  final VoidCallback onApply;
  final VoidCallback onReview;
  final VoidCallback onIgnore;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final risk = const SecretaryTodoCommandRiskPolicy().classify(command);
    final accent = _accentFor(context, risk);
    final t = context.t;
    final canApply = secretaryTodoCommandCanApplyFromCard(command);
    final canReview = secretaryTodoCommandCanOpenReview(command);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SlSurface(
          color: colorScheme.surface,
          borderColor: accent.withOpacity(0.28),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          padding: const EdgeInsets.all(14),
          child: Column(
            key: ValueKey('secretary_todo_command_card_${command.id}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(_iconFor(risk), size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.chat.secretary.todoCommand.cardTitle,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Text(
                    _confidenceLabel(command.confidence),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                secretaryTodoCommandPreview(context, command),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              for (final detail in _detailLines(command)) ...[
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (_supportingText(command) != null) ...[
                const SizedBox(height: 6),
                Text(
                  _supportingText(command)!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (canApply)
                    SlButton(
                      buttonKey: ValueKey(
                          'secretary_todo_command_apply_${command.id}'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      onPressed: onApply,
                      child: Text(t.common.actions.apply),
                    ),
                  if (canReview)
                    SlButton(
                      buttonKey: ValueKey(
                        'secretary_todo_command_review_${command.id}',
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      variant: canApply
                          ? SlButtonVariant.outline
                          : SlButtonVariant.primary,
                      onPressed: onReview,
                      child: Text(
                        risk == SecretaryTodoCommandRisk.confirm
                            ? t.chat.secretary.todoCommand.confirm
                            : t.chat.secretary.todoCommand.review,
                      ),
                    ),
                  if (onEdit != null)
                    SlButton(
                      buttonKey:
                          ValueKey('secretary_todo_command_edit_${command.id}'),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      variant: SlButtonVariant.outline,
                      onPressed: onEdit,
                      child: Text(t.common.actions.edit),
                    ),
                  SlButton(
                    buttonKey:
                        ValueKey('secretary_todo_command_ignore_${command.id}'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    variant: SlButtonVariant.outline,
                    onPressed: onIgnore,
                    child: Text(t.common.actions.ignore),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accentFor(BuildContext context, SecretaryTodoCommandRisk risk) {
    return switch (risk) {
      SecretaryTodoCommandRisk.confirm => Theme.of(context).colorScheme.error,
      SecretaryTodoCommandRisk.review => Colors.orange.shade700,
      SecretaryTodoCommandRisk.autoApply =>
        Theme.of(context).colorScheme.primary,
      SecretaryTodoCommandRisk.reject => Theme.of(context).colorScheme.outline,
    };
  }

  IconData _iconFor(SecretaryTodoCommandRisk risk) {
    return switch (risk) {
      SecretaryTodoCommandRisk.confirm => Icons.warning_amber_rounded,
      SecretaryTodoCommandRisk.review => Icons.rule_rounded,
      SecretaryTodoCommandRisk.autoApply => Icons.check_circle_outline_rounded,
      SecretaryTodoCommandRisk.reject => Icons.help_outline_rounded,
    };
  }

  String _confidenceLabel(double confidence) {
    if (!confidence.isFinite) return '';
    return '${(confidence * 100).round()}%';
  }

  String? _supportingText(SecretaryTodoCommand command) {
    final raw = command.rawText?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  List<String> _detailLines(SecretaryTodoCommand command) {
    if (command.kind != SecretaryTodoCommandKind.updateTitle) {
      return const <String>[];
    }
    return [
      if (command.targetTitle?.trim().isNotEmpty == true)
        command.targetTitle!.trim(),
      if (command.newTitle?.trim().isNotEmpty == true) command.newTitle!.trim(),
    ];
  }
}

bool secretaryTodoCommandCanApplyFromCard(SecretaryTodoCommand command) {
  final risk = const SecretaryTodoCommandRiskPolicy().classify(command);
  return risk == SecretaryTodoCommandRisk.review && command.isValid;
}

bool secretaryTodoCommandCanOpenReview(SecretaryTodoCommand command) {
  final risk = const SecretaryTodoCommandRiskPolicy().classify(command);
  return command.isValid &&
      (risk == SecretaryTodoCommandRisk.review ||
          risk == SecretaryTodoCommandRisk.confirm);
}

String secretaryTodoCommandPreview(
  BuildContext context,
  SecretaryTodoCommand command,
) {
  final t = context.t.chat.secretary.todoCommand;
  final title = _targetTitle(command);
  return switch (command.kind) {
    SecretaryTodoCommandKind.updateTitle => t.preview.rename(
        from: title,
        to: _textOrFallback(command.newTitle, t.unknownTarget),
      ),
    SecretaryTodoCommandKind.reschedule => t.preview.move(
        title: title,
        time: _formatDueAt(context, command.dueAtMs),
      ),
    SecretaryTodoCommandKind.setStatus => t.preview.status(
        title: title,
        status: _statusLabel(context, command.newStatus),
      ),
    SecretaryTodoCommandKind.dismiss => t.preview.delete(title: title),
    SecretaryTodoCommandKind.reprioritize =>
      _priorityPreview(context, command, title),
    SecretaryTodoCommandKind.create ||
    SecretaryTodoCommandKind.batchUpdate ||
    SecretaryTodoCommandKind.none =>
      t.preview.unsupported,
  };
}

String _priorityPreview(
  BuildContext context,
  SecretaryTodoCommand command,
  String title,
) {
  final t = context.t.chat.secretary.todoCommand.preview;
  final importance = command.manualImportanceNudgeScore ?? 0;
  final urgency = command.manualUrgencyNudgeScore ?? 0;
  if (urgency > 0 && importance <= 0) return t.priorityUrgentUp(title: title);
  if (urgency < 0 && importance >= 0) {
    return t.priorityUrgentDown(title: title);
  }
  if (importance < 0 || urgency < 0) return t.priorityDown(title: title);
  return t.priorityUp(title: title);
}

String _targetTitle(SecretaryTodoCommand command) {
  final targetTitle = command.targetTitle?.trim();
  if (targetTitle != null && targetTitle.isNotEmpty) return targetTitle;
  final targetTodoId = command.targetTodoId?.trim();
  if (targetTodoId != null && targetTodoId.isNotEmpty) return targetTodoId;
  return command.rawText?.trim().isNotEmpty == true
      ? command.rawText!.trim()
      : '';
}

String _textOrFallback(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}

String _statusLabel(BuildContext context, String? status) {
  final t = context.t.chat.secretary.todoCommand.status;
  return switch ((status ?? '').trim()) {
    'done' => t.done,
    'in_progress' => t.inProgress,
    'dismissed' => t.dismissed,
    'open' || 'inbox' => t.open,
    _ => t.unknown,
  };
}

String _formatDueAt(BuildContext context, int? dueAtMs) {
  if (dueAtMs == null) {
    return context.t.chat.secretary.todoCommand.unknownTime;
  }
  final localizations = MaterialLocalizations.of(context);
  final value = DateTime.fromMillisecondsSinceEpoch(dueAtMs).toLocal();
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(value),
    alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
  );
  final now = DateTime.now();
  if (value.year == now.year &&
      value.month == now.month &&
      value.day == now.day) {
    return time;
  }
  return '${localizations.formatShortDate(value)} $time';
}
