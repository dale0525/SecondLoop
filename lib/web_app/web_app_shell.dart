import 'package:flutter/material.dart';

import '../ui/sl_glass.dart';
import '../ui/sl_surface.dart';
import '../ui/sl_tokens.dart';

const double _kWideWebAppShellBreakpoint = 720;
const double _kWebAppShellMaxWidth = 1240;

class WebAppShellDestination {
  const WebAppShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class WebAppShell extends StatelessWidget {
  const WebAppShell({
    required this.title,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.child,
    super.key,
  });

  final String title;
  final int selectedIndex;
  final List<WebAppShellDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideShell =
            constraints.maxWidth >= _kWideWebAppShellBreakpoint;
        final clippedChild = ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          child: child,
        );

        if (useWideShell) {
          return Scaffold(
            resizeToAvoidBottomInset: false,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kWebAppShellMaxWidth,
                  ),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 92,
                          child: SlGlass(
                            borderRadius:
                                BorderRadius.circular(tokens.radiusLg),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: NavigationRail(
                              selectedIndex: selectedIndex,
                              onDestinationSelected: onDestinationSelected,
                              labelType: NavigationRailLabelType.all,
                              leading: _WebAppShellRailTitle(title: title),
                              destinations: [
                                for (final destination in destinations)
                                  NavigationRailDestination(
                                    icon: Icon(destination.icon),
                                    selectedIcon:
                                        Icon(destination.selectedIcon),
                                    label: Text(destination.label),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SlPageSurface(
                          margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                          child: clippedChild,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(title: Text(title)),
          body: SlPageSurface(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: clippedChild,
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                ),
            ],
          ),
        );
      },
    );
  }
}

class WebAppPanelFrame extends StatelessWidget {
  const WebAppPanelFrame({
    required this.child,
    super.key,
    this.maxWidth = 880,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideShell =
            constraints.maxWidth >= _kWideWebAppShellBreakpoint;
        return SlPageSurface(
          maxWidth: maxWidth,
          margin: useWideShell
              ? const EdgeInsets.all(24)
              : const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            child: child,
          ),
        );
      },
    );
  }
}

final class _WebAppShellRailTitle extends StatelessWidget {
  const _WebAppShellRailTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
