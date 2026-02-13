part of 'todo_detail_page.dart';

enum _MessageAction {
  copy,
  linkTodo,
  edit,
  delete,
}

final class _TodoDueChip extends StatelessWidget {
  const _TodoDueChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.chipKey,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Key? chipKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final colorScheme = theme.colorScheme;

    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.pressed)) {
        return colorScheme.primary.withOpacity(0.16);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return colorScheme.primary.withOpacity(0.12);
      }
      return null;
    });

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: OutlinedButton.icon(
        key: chipKey,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
          backgroundColor: tokens.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          side: BorderSide(color: tokens.borderSubtle),
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(overlayColor: overlay),
        icon: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
