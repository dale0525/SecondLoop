import 'package:flutter/material.dart';

import 'agent_design_tokens.dart';

@immutable
final class AgentTabItem {
  const AgentTabItem({
    required this.id,
    required this.label,
    this.icon,
  });

  final String id;
  final String label;
  final IconData? icon;
}

final class AgentTabBar extends StatelessWidget {
  const AgentTabBar({
    required this.tabs,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<AgentTabItem> tabs;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tab in tabs) ...[
            _AgentTabButton(
              tab: tab,
              selected: tab.id == selectedId,
              onSelected: onSelected,
              scheme: scheme,
            ),
            if (tab != tabs.last)
              const SizedBox(width: AgentDesignTokens.gapSm),
          ],
        ],
      ),
    );
  }
}

final class _AgentTabButton extends StatelessWidget {
  const _AgentTabButton({
    required this.tab,
    required this.selected,
    required this.onSelected,
    required this.scheme,
  });

  final AgentTabItem tab;
  final bool selected;
  final ValueChanged<String> onSelected;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final borderColor =
        selected ? scheme.primary.withOpacity(0.34) : scheme.outlineVariant;
    final background =
        selected ? scheme.primaryContainer.withOpacity(0.72) : scheme.surface;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        key: selected ? ValueKey('agent_tab_${tab.id}_selected') : null,
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgentDesignTokens.radiusSm),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AgentDesignTokens.radiusSm),
          onTap: () => onSelected(tab.id),
          child: Padding(
            padding: AgentDesignTokens.tabPadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.icon != null) ...[
                  Icon(tab.icon, size: 16, color: foreground),
                  const SizedBox(width: AgentDesignTokens.gapSm),
                ],
                Text(
                  tab.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
