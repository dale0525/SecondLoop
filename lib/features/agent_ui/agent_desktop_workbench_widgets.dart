import 'package:flutter/material.dart';

import 'agent_operating_system_tokens.dart';

final class DesktopWorkbenchPageShell extends StatelessWidget {
  const DesktopWorkbenchPageShell({
    required this.child,
    this.maxWidth,
    super.key,
  });

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = AgentOperatingSystemTokens.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(32),
      child: child,
    );
    return ColoredBox(
      color: colors.background,
      child: maxWidth == null
          ? content
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth!),
                child: content,
              ),
            ),
    );
  }
}

final class DesktopWorkbenchHeader extends StatelessWidget {
  const DesktopWorkbenchHeader({
    required this.title,
    required this.subtitle,
    this.actions = const <Widget>[],
    this.bottom,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final colors = AgentOperatingSystemTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 34 / 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ).copyWith(color: colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AgentOperatingSystemTokens.bodyMd.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 16),
              Wrap(spacing: 12, runSpacing: 8, children: actions),
            ],
          ],
        ),
        if (bottom != null) ...[
          const SizedBox(height: 20),
          bottom!,
        ],
      ],
    );
  }
}

final class DesktopWorkbenchPanel extends StatelessWidget {
  const DesktopWorkbenchPanel({
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AgentOperatingSystemTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: colors.surfaceContainerLow,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgentOperatingSystemTokens.headlineSm.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: trailing!,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              color: colors.outlineVariant,
            ),
            Expanded(
              child: Padding(
                padding: padding,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class DesktopWorkbenchBadge extends StatelessWidget {
  const DesktopWorkbenchBadge({
    required this.label,
    this.background,
    this.foreground,
    this.border,
    super.key,
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final colors = AgentOperatingSystemTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: foreground ?? colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

final class DesktopWorkbenchEmptyState extends StatelessWidget {
  const DesktopWorkbenchEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AgentOperatingSystemTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: colors.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AgentOperatingSystemTokens.headlineSm.copyWith(
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AgentOperatingSystemTokens.bodySm.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showDesktopWorkbenchMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
