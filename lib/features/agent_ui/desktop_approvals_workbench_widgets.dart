part of 'desktop_approvals_workbench_page.dart';

final class _CodePair extends StatelessWidget {
  const _CodePair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: colors.outline),
          ),
          TextSpan(text: value),
        ],
      ),
      style: AgentOperatingSystemTokens.code.copyWith(
        color: colors.onSurfaceVariant,
      ),
    );
  }
}

final class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: AgentOperatingSystemTokens.code.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
