part of 'todo_detail_page.dart';

final class _TodoStatusSelector extends StatelessWidget {
  const _TodoStatusSelector({
    required this.statuses,
    required this.selectedStatus,
    required this.statusLabelBuilder,
    required this.onSelected,
    this.buttonKeyBuilder,
  });

  final List<String> statuses;
  final String selectedStatus;
  final String Function(String status) statusLabelBuilder;
  final ValueChanged<String> onSelected;
  final Key? Function(String status)? buttonKeyBuilder;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final status in statuses)
          _TodoStatusButton(
            buttonKey: buttonKeyBuilder?.call(status),
            label: statusLabelBuilder(status),
            selected: status == selectedStatus,
            onPressed: () {
              if (status == selectedStatus) return;
              onSelected(status);
            },
          ),
      ],
    );
  }
}

final class _TodoStatusButton extends StatelessWidget {
  const _TodoStatusButton({
    required this.label,
    required this.onPressed,
    required this.selected,
    this.buttonKey,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      final base = selected ? colorScheme.primary : colorScheme.onSurface;
      if (states.contains(MaterialState.pressed)) {
        return base.withOpacity(0.16);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return base.withOpacity(0.1);
      }
      return null;
    });

    final foreground =
        selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final border = selected
        ? colorScheme.primary.withOpacity(
            theme.brightness == Brightness.dark ? 0.58 : 0.4,
          )
        : tokens.borderSubtle;
    final background = selected
        ? colorScheme.primary.withOpacity(
            theme.brightness == Brightness.dark ? 0.2 : 0.08,
          )
        : tokens.surface2;

    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        side: BorderSide(color: border),
      ).copyWith(overlayColor: overlay),
      icon: Icon(
        selected ? Icons.check_rounded : Icons.circle_outlined,
        size: 16,
        color: foreground,
      ),
      label: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

final class _TodoStatusChangeTransition extends StatelessWidget {
  const _TodoStatusChangeTransition({
    required this.fromStatusLabel,
    required this.toStatusLabel,
  });

  final String fromStatusLabel;
  final String toStatusLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      key: const ValueKey('todo_detail_status_change_transition'),
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _TodoStatusPill(
          pillKey: const ValueKey('todo_detail_status_change_from'),
          label: fromStatusLabel,
          emphasize: false,
        ),
        Icon(
          Icons.east_rounded,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
        _TodoStatusPill(
          pillKey: const ValueKey('todo_detail_status_change_to'),
          label: toStatusLabel,
          emphasize: true,
        ),
      ],
    );
  }
}

final class _TodoStatusPill extends StatelessWidget {
  const _TodoStatusPill({
    required this.label,
    required this.emphasize,
    this.pillKey,
  });

  final String label;
  final bool emphasize;
  final Key? pillKey;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final foreground =
        emphasize ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final background = emphasize
        ? colorScheme.primary.withOpacity(isDark ? 0.2 : 0.08)
        : tokens.surface2;
    final border = emphasize
        ? colorScheme.primary.withOpacity(isDark ? 0.58 : 0.4)
        : tokens.borderSubtle;

    return DecoratedBox(
      key: pillKey,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
