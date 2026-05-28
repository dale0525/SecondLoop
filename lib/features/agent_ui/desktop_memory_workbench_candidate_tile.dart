part of 'desktop_memory_workbench_page.dart';

final class _MemoryCandidateTile extends StatelessWidget {
  const _MemoryCandidateTile({
    required this.candidate,
    required this.busy,
    required this.onApprove,
    required this.onDismiss,
  });

  final _MemoryCandidate candidate;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = AgentOperatingSystemTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.lightbulb_rounded,
              size: 18,
              color: colors.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                candidate.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              key: ValueKey('desktop_memory_candidate_dismiss_${candidate.id}'),
              onPressed: busy ? null : onDismiss,
              child: Text(context.t.common.actions.dismiss),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ValueKey('desktop_memory_candidate_approve_${candidate.id}'),
              onPressed: busy ? null : onApprove,
              child: busy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t.common.actions.approve),
            ),
          ],
        ),
      ),
    );
  }
}
