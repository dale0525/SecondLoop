part of 'welcome_page.dart';

final class _WelcomeShellColors {
  const _WelcomeShellColors({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.borderSubtle,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.selected,
  });

  final Color background;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color borderSubtle;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color selected;

  static _WelcomeShellColors of(BuildContext context) {
    final tokens = SlTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _WelcomeShellColors(
      background: tokens.background,
      surface: tokens.surface,
      surface2: tokens.surface2,
      border: tokens.border,
      borderSubtle: tokens.borderSubtle,
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      selected: scheme.primaryContainer,
    );
  }
}

class _WelcomeContentPane extends StatelessWidget {
  const _WelcomeContentPane({
    required this.children,
    this.footer,
  });

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = _WelcomeShellColors.of(context);
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
          if (footer != null) ...[
            const _WelcomeShellDivider(horizontal: true),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _WelcomeModeCards extends StatelessWidget {
  const _WelcomeModeCards({
    required this.managedCard,
    required this.selfManagedCard,
  });

  final Widget managedCard;
  final Widget selfManagedCard;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 680) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: managedCard),
              const SizedBox(width: AgentDesignTokens.gapMd),
              Expanded(child: selfManagedCard),
            ],
          );
        }

        return Column(
          children: [
            managedCard,
            const SizedBox(height: AgentDesignTokens.gapMd),
            selfManagedCard,
          ],
        );
      },
    );
  }
}

class _WelcomeGuideCard extends StatelessWidget {
  const _WelcomeGuideCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.comparisonTitle,
    required this.comparisonItems,
    required this.comparisonKey,
    required this.comparisonPositive,
    required this.statusLabel,
    required this.statusKey,
    required this.ready,
    required this.actionKey,
    required this.actionLabel,
    required this.onActionTap,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final String description;
  final String comparisonTitle;
  final List<String> comparisonItems;
  final Key comparisonKey;
  final bool comparisonPositive;
  final String statusLabel;
  final Key statusKey;
  final bool ready;
  final Key actionKey;
  final String actionLabel;
  final VoidCallback onActionTap;

  @override
  Widget build(BuildContext context) {
    final colors = _WelcomeShellColors.of(context);
    final borderColor = ready ? colors.accent.withOpacity(0.28) : colors.border;
    final iconBackground = ready ? colors.selected : colors.surface2;

    return SlSurface(
      key: cardKey,
      color: colors.surface,
      borderColor: borderColor,
      borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius:
                        BorderRadius.circular(AgentDesignTokens.radiusSm),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    icon,
                    color: colors.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AgentDesignTokens.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: colors.text,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AgentDesignTokens.gapMd),
                          _WelcomeStatusBadge(
                            label: statusLabel,
                            badgeKey: statusKey,
                            ready: ready,
                          ),
                        ],
                      ),
                      const SizedBox(height: AgentDesignTokens.gapXs),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.muted,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _WelcomeComparisonList(
              listKey: comparisonKey,
              title: comparisonTitle,
              items: comparisonItems,
              positive: comparisonPositive,
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _WelcomeShellButton(
              buttonKey: actionKey,
              label: actionLabel,
              icon: Icons.arrow_forward_rounded,
              onPressed: onActionTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeComparisonList extends StatelessWidget {
  const _WelcomeComparisonList({
    required this.listKey,
    required this.title,
    required this.items,
    required this.positive,
  });

  final Key listKey;
  final String title;
  final List<String> items;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final colors = _WelcomeShellColors.of(context);
    final icon = positive
        ? Icons.check_circle_rounded
        : Icons.radio_button_unchecked_rounded;
    final iconColor = positive ? colors.accent : colors.muted;

    return Column(
      key: listKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        for (final item in items) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: AgentDesignTokens.gapSm),
              Expanded(
                child: Text(
                  item,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.muted,
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
          if (item != items.last)
            const SizedBox(height: AgentDesignTokens.gapSm),
        ],
      ],
    );
  }
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    required this.title,
    required this.description,
    required this.statusLabel,
    required this.statusKey,
    required this.unavailableHint,
    required this.permissionTiles,
    required this.statusLabelFor,
    required this.onPermissionTap,
  });

  final String title;
  final String description;
  final String statusLabel;
  final Key statusKey;
  final String unavailableHint;
  final List<_PermissionTileData> permissionTiles;
  final String Function(_PermissionStatus status) statusLabelFor;
  final ValueChanged<_PermissionItem> onPermissionTap;

  @override
  Widget build(BuildContext context) {
    final colors = _WelcomeShellColors.of(context);
    final permissionsReady =
        statusLabel.toLowerCase() == 'enabled' || statusLabel == '已开启';

    return SlSurface(
      key: const ValueKey('welcome_guide_card_permissions'),
      color: colors.surface,
      borderColor: colors.border,
      borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: colors.text,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: AgentDesignTokens.gapXs),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.muted,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AgentDesignTokens.gapMd),
                _WelcomeStatusBadge(
                  label: statusLabel,
                  badgeKey: statusKey,
                  ready: permissionsReady,
                ),
              ],
            ),
          ),
          if (permissionTiles.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AgentDesignTokens.gapLg,
                0,
                AgentDesignTokens.gapLg,
                AgentDesignTokens.gapLg,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  unavailableHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.muted,
                      ),
                ),
              ),
            )
          else
            for (var i = 0; i < permissionTiles.length; i++) ...[
              const _WelcomeShellDivider(horizontal: true),
              _PermissionTile(
                tileKey: permissionTiles[i].key,
                icon: permissionTiles[i].icon,
                label: permissionTiles[i].label,
                reason: permissionTiles[i].reason,
                statusLabel: statusLabelFor(permissionTiles[i].status),
                statusKey: ValueKey(
                  'welcome_guide_permission_status_${permissionTiles[i].item.keySuffix}_${permissionTiles[i].status.keySuffix}',
                ),
                ready: permissionTiles[i].status == _PermissionStatus.enabled,
                onTap: () => onPermissionTap(permissionTiles[i].item),
              ),
            ],
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.reason,
    required this.statusLabel,
    required this.statusKey,
    required this.ready,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String label;
  final String reason;
  final String statusLabel;
  final Key statusKey;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _WelcomeShellColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AgentDesignTokens.gapLg,
            vertical: AgentDesignTokens.gapMd,
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.muted, size: 20),
              const SizedBox(width: AgentDesignTokens.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AgentDesignTokens.gapXs),
                    Text(
                      reason,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.muted,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AgentDesignTokens.gapMd),
              _WelcomeStatusBadge(
                label: statusLabel,
                badgeKey: statusKey,
                ready: ready,
              ),
              const SizedBox(width: AgentDesignTokens.gapSm),
              Icon(
                Icons.open_in_new_rounded,
                color: colors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeFooter extends StatelessWidget {
  const _WelcomeFooter({
    required this.skipLabel,
    required this.finishLabel,
    required this.onSkip,
    required this.onFinish,
  });

  final String skipLabel;
  final String finishLabel;
  final VoidCallback onSkip;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
        child: Row(
          children: [
            _WelcomeShellButton(
              buttonKey: const ValueKey('welcome_guide_skip'),
              label: skipLabel,
              onPressed: onSkip,
              outlined: true,
            ),
            const SizedBox(width: AgentDesignTokens.gapMd),
            Expanded(
              child: _WelcomeShellButton(
                buttonKey: const ValueKey('welcome_guide_finish'),
                label: finishLabel,
                onPressed: onFinish,
                primary: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeShellButton extends StatelessWidget {
  const _WelcomeShellButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.outlined = false,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool primary;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final colors = _WelcomeShellColors.of(context);
    final foreground = primary ? colors.onAccent : colors.accent;
    final background = primary
        ? colors.accent
        : outlined
            ? colors.surface
            : colors.selected;
    final side = outlined ? BorderSide(color: colors.border) : BorderSide.none;
    final style = FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: colors.borderSubtle,
      disabledForegroundColor: colors.muted,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgentDesignTokens.radiusSm),
        side: side,
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    );

    if (icon == null) {
      return FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }

    return FilledButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _WelcomeStatusBadge extends StatelessWidget {
  const _WelcomeStatusBadge({
    required this.label,
    required this.badgeKey,
    required this.ready,
  });

  final String label;
  final Key badgeKey;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final colors = _WelcomeShellColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ready ? colors.selected : colors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          key: badgeKey,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: ready ? colors.accent : colors.muted,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _WelcomeShellDivider extends StatelessWidget {
  const _WelcomeShellDivider({this.horizontal = false});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final colors = _WelcomeShellColors.of(context);
    return SizedBox(
      width: horizontal ? double.infinity : 1,
      height: horizontal ? 1 : double.infinity,
      child: ColoredBox(color: colors.border),
    );
  }
}
