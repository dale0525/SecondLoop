import 'package:flutter/material.dart';

import '../../core/secretary/todo_command_executor.dart';
import '../../core/secretary/todo_command_models.dart';
import '../../core/secretary/todo_command_risk_policy.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'secretary_review_section.dart';
import 'todo_command_review_card.dart';

class TodoCommandReviewPage extends StatefulWidget {
  const TodoCommandReviewPage({
    required this.commands,
    required this.executor,
    this.onApplied,
    this.onIgnored,
    this.onEdit,
    super.key,
  });

  final List<SecretaryTodoCommand> commands;
  final TodoCommandExecutor executor;
  final ValueChanged<SecretaryTodoCommandExecutionResult>? onApplied;
  final ValueChanged<SecretaryTodoCommand>? onIgnored;
  final ValueChanged<SecretaryTodoCommand>? onEdit;

  @override
  State<TodoCommandReviewPage> createState() => _TodoCommandReviewPageState();
}

class _TodoCommandReviewPageState extends State<TodoCommandReviewPage> {
  final Set<String> _handledCommandIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.secretary.todoCommand;
    final pending = widget.commands
        .where((command) => !_handledCommandIds.contains(command.id))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(t.pageTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: pending.isEmpty
              ? Center(child: Text(t.empty))
              : SecretaryReviewSection(
                  title: t.pendingSection,
                  count: pending.length,
                  children: [
                    for (final command in pending)
                      _TodoCommandTile(
                        command: command,
                        onApply: () => _apply(command),
                        onIgnore: () => _ignore(command),
                        onEdit: widget.onEdit == null
                            ? null
                            : () => widget.onEdit!(command),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _apply(SecretaryTodoCommand command) async {
    final result = await widget.executor.execute(command, confirmed: true);
    if (!mounted) return;
    if (result.applied) {
      widget.onApplied?.call(result);
      setState(() => _handledCommandIds.add(command.id));
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
              content: Text(context.t.chat.secretary.todoCommand.appliedSnack)),
        );
      return;
    }

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
            content: Text(context.t.chat.secretary.todoCommand.failedSnack)),
      );
  }

  void _ignore(SecretaryTodoCommand command) {
    widget.onIgnored?.call(command);
    setState(() => _handledCommandIds.add(command.id));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
            content: Text(context.t.chat.secretary.todoCommand.ignoredSnack)),
      );
  }
}

class _TodoCommandTile extends StatelessWidget {
  const _TodoCommandTile({
    required this.command,
    required this.onApply,
    required this.onIgnore,
    this.onEdit,
  });

  final SecretaryTodoCommand command;
  final VoidCallback onApply;
  final VoidCallback onIgnore;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = SlTokens.of(context);
    final t = context.t;
    final risk = const SecretaryTodoCommandRiskPolicy().classify(command);
    final canApply = command.isValid && risk != SecretaryTodoCommandRisk.reject;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SlSurface(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  risk == SecretaryTodoCommandRisk.confirm
                      ? Icons.warning_amber_rounded
                      : Icons.rule_rounded,
                  color: risk == SecretaryTodoCommandRisk.confirm
                      ? colorScheme.error
                      : colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    secretaryTodoCommandPreview(context, command),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            if (command.rawText?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                command.rawText!.trim(),
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canApply)
                  SlButton(
                    buttonKey: ValueKey(
                      risk == SecretaryTodoCommandRisk.confirm
                          ? 'todo_command_review_confirm_${command.id}'
                          : 'todo_command_review_apply_${command.id}',
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    onPressed: onApply,
                    child: Text(
                      risk == SecretaryTodoCommandRisk.confirm
                          ? t.chat.secretary.todoCommand.confirmDelete
                          : t.common.actions.apply,
                    ),
                  ),
                if (onEdit != null)
                  SlButton(
                    buttonKey:
                        ValueKey('todo_command_review_edit_${command.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    variant: SlButtonVariant.outline,
                    onPressed: onEdit,
                    child: Text(t.common.actions.edit),
                  ),
                SlButton(
                  buttonKey:
                      ValueKey('todo_command_review_ignore_${command.id}'),
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
    );
  }
}
