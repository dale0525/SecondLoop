import 'package:flutter/material.dart';

import 'app_shell_default_pages_stub.dart'
    if (dart.library.io) 'app_shell_default_pages_io.dart'
    if (dart.library.html) 'app_shell_default_pages_web.dart'
    as app_shell_defaults;
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/quick_capture/quick_capture_scope.dart';
import '../core/update/update_badge_prefs.dart';
import '../i18n/strings.g.dart';
import '../ui/sl_glass.dart';
import '../ui/sl_surface.dart';
import '../ui/sl_tokens.dart';

const _kDesktopShellMaxWidth = 1240.0;

enum AppTab {
  chat(Icons.chat_bubble_outline, Icons.chat_bubble),
  settings(Icons.settings_outlined, Icons.settings);

  const AppTab(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String label(BuildContext context) => switch (this) {
        AppTab.chat => context.t.app.tabs.main,
        AppTab.settings => context.t.app.tabs.settings,
      };
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialTab = AppTab.chat,
    this.chatTabBuilder,
    this.settingsTabBuilder,
  });

  final AppTab initialTab;
  final Widget Function(BuildContext context, bool isActive)? chatTabBuilder;
  final Widget Function(BuildContext context, bool isActive)?
      settingsTabBuilder;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex = widget.initialTab.index;
  late final Set<int> _loadedIndexes = <int>{_selectedIndex};
  QuickCaptureController? _quickCaptureController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final controller = QuickCaptureScope.maybeOf(context);
    if (_quickCaptureController == controller) return;

    _quickCaptureController?.removeListener(_onQuickCaptureChanged);
    _quickCaptureController = controller;
    if (controller != null) {
      controller.addListener(_onQuickCaptureChanged);
    }
  }

  void _onQuickCaptureChanged() {
    final controller = _quickCaptureController;
    if (controller == null) return;

    final shouldOpenChat = controller.consumeOpenChatRequest();
    if (!shouldOpenChat || _selectedIndex == 0 || !mounted) {
      return;
    }

    _selectTab(0);
  }

  @override
  void dispose() {
    _quickCaptureController?.removeListener(_onQuickCaptureChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _selectedIndex = widget.initialTab.index;
      _loadedIndexes.add(_selectedIndex);
    }
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
      _loadedIndexes.add(index);
    });
  }

  Widget _buildWideShellTab(
    BuildContext context,
    AppTab tab, {
    required bool isActive,
  }) {
    if (!_loadedIndexes.contains(tab.index)) {
      return const SizedBox.shrink();
    }
    return switch (tab) {
      AppTab.chat => _buildChatTab(context, isActive: isActive),
      AppTab.settings => _buildSettingsTab(context, isActive: isActive),
    };
  }

  Widget _buildChatTab(BuildContext context, {required bool isActive}) {
    final builder = widget.chatTabBuilder;
    if (builder != null) return builder(context, isActive);
    return app_shell_defaults.buildDefaultChatTab(
      context,
      isActive: isActive,
    );
  }

  Widget _buildSettingsTab(BuildContext context, {required bool isActive}) {
    final builder = widget.settingsTabBuilder;
    if (builder != null) return builder(context, isActive);
    return app_shell_defaults.buildDefaultSettingsTab(
      context,
      isActive: isActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final mediaQuery = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useCollapsedShell = constraints.maxHeight < 180;
        final useRail = !useCollapsedShell && constraints.maxWidth >= 720;
        final content = useRail
            ? IndexedStack(
                index: _selectedIndex,
                children: <Widget>[
                  _buildWideShellTab(
                    context,
                    AppTab.chat,
                    isActive: _selectedIndex == 0,
                  ),
                  _buildWideShellTab(
                    context,
                    AppTab.settings,
                    isActive: _selectedIndex == 1,
                  ),
                ],
              )
            : _buildChatTab(context, isActive: true);

        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: useCollapsedShell
              ? const SizedBox.shrink()
              : useRail
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _kDesktopShellMaxWidth,
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: NavigationRail(
                                    selectedIndex: _selectedIndex,
                                    onDestinationSelected: _selectTab,
                                    labelType: NavigationRailLabelType.all,
                                    destinations: [
                                      for (final t in AppTab.values)
                                        NavigationRailDestination(
                                          icon: t == AppTab.settings
                                              ? _AppUpdateBadgeIcon(
                                                  icon: t.icon,
                                                  badgeKey: const ValueKey(
                                                    'app_tab_settings_update_badge',
                                                  ),
                                                )
                                              : Icon(t.icon),
                                          selectedIcon: t == AppTab.settings
                                              ? _AppUpdateBadgeIcon(
                                                  icon: t.selectedIcon,
                                                  badgeKey: const ValueKey(
                                                    'app_tab_settings_update_badge_selected',
                                                  ),
                                                )
                                              : Icon(t.selectedIcon),
                                          label: Text(t.label(context)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: SlPageSurface(
                                margin:
                                    const EdgeInsets.fromLTRB(0, 12, 12, 12),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(tokens.radiusLg),
                                  child: content,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SlPageSurface(
                      margin: EdgeInsets.fromLTRB(
                        12,
                        12 + mediaQuery.viewPadding.top,
                        12,
                        0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(tokens.radiusLg),
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          child: content,
                        ),
                      ),
                    ),
          bottomNavigationBar: null,
        );
      },
    );
  }
}

final class _AppUpdateBadgeIcon extends StatelessWidget {
  const _AppUpdateBadgeIcon({
    required this.icon,
    required this.badgeKey,
  });

  final IconData icon;
  final Key badgeKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: UpdateBadgePrefs.value,
      builder: (context, latestTag, child) {
        final hasUpdate = latestTag != null && latestTag.trim().isNotEmpty;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon),
            if (hasUpdate)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  key: badgeKey,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
