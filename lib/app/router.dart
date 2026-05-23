import 'package:flutter/material.dart';

import 'app_shell_default_pages_stub.dart'
    if (dart.library.io) 'app_shell_default_pages_io.dart'
    if (dart.library.html) 'app_shell_default_pages_web.dart'
    as app_shell_defaults;
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/quick_capture/quick_capture_scope.dart';
import '../core/update/update_badge_prefs.dart';
import 'app_shell_style.dart';
import 'theme.dart';

enum AppTab {
  review(Icons.summarize_outlined, Icons.summarize),
  conversation(Icons.chat_bubble_outline, Icons.chat_bubble),
  notes(Icons.inventory_2_outlined, Icons.inventory_2),
  memory(Icons.checklist_outlined, Icons.checklist),
  settings(Icons.settings_outlined, Icons.settings);

  const AppTab(this.icon, this.selectedIcon);

  static const chat = conversation;

  final IconData icon;
  final IconData selectedIcon;

  String label(BuildContext context) => switch (this) {
        AppTab.review => 'Briefing',
        AppTab.conversation => 'Chat',
        AppTab.notes => 'Vault',
        AppTab.memory => 'Tasks',
        AppTab.settings => 'Settings',
      };
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialTab = AppTab.conversation,
    this.conversationTabBuilder,
    this.chatTabBuilder,
    this.notesTabBuilder,
    this.memoryTabBuilder,
    this.reviewTabBuilder,
    this.settingsTabBuilder,
  });

  final AppTab initialTab;
  final Widget Function(BuildContext context, bool isActive)?
      conversationTabBuilder;
  final Widget Function(BuildContext context, bool isActive)? chatTabBuilder;
  final Widget Function(BuildContext context, bool isActive)? notesTabBuilder;
  final Widget Function(BuildContext context, bool isActive)? memoryTabBuilder;
  final Widget Function(BuildContext context, bool isActive)? reviewTabBuilder;
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
    if (!shouldOpenChat ||
        _selectedIndex == AppTab.conversation.index ||
        !mounted) {
      return;
    }

    _selectTab(AppTab.conversation.index);
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
      AppTab.conversation => _buildConversationTab(context, isActive: isActive),
      AppTab.notes => _buildNotesTab(context, isActive: isActive),
      AppTab.memory => _buildMemoryTab(context, isActive: isActive),
      AppTab.review => _buildReviewTab(context, isActive: isActive),
      AppTab.settings => _buildSettingsTab(context, isActive: isActive),
    };
  }

  Widget _buildConversationTab(
    BuildContext context, {
    required bool isActive,
  }) {
    final builder = widget.conversationTabBuilder ?? widget.chatTabBuilder;
    if (builder != null) return builder(context, isActive);
    return app_shell_defaults.buildDefaultChatTab(
      context,
      isActive: isActive,
    );
  }

  Widget _buildNotesTab(BuildContext context, {required bool isActive}) {
    final builder = widget.notesTabBuilder;
    if (builder != null) return builder(context, isActive);
    return app_shell_defaults.buildDefaultNotesTab(
      context,
      isActive: isActive,
    );
  }

  Widget _buildMemoryTab(BuildContext context, {required bool isActive}) {
    final builder = widget.memoryTabBuilder;
    if (builder != null) return builder(context, isActive);
    return app_shell_defaults.buildDefaultMemoryTab(
      context,
      isActive: isActive,
    );
  }

  Widget _buildReviewTab(BuildContext context, {required bool isActive}) {
    final builder = widget.reviewTabBuilder;
    if (builder != null) return builder(context, isActive);
    return app_shell_defaults.buildDefaultReviewTab(
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
    final parentTheme = Theme.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    return Theme(
      data: AppTheme.light(locale: locale, platform: parentTheme.platform),
      child: Builder(
        builder: (context) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final useCollapsedShell = constraints.maxHeight < 180;
              final useRail = !useCollapsedShell && constraints.maxWidth >= 960;
              final useBottomNav = !useCollapsedShell && !useRail;
              final content = useRail || useBottomNav
                  ? IndexedStack(
                      index: _selectedIndex,
                      children: [
                        for (final tab in AppTab.values)
                          _buildWideShellTab(
                            context,
                            tab,
                            isActive: _selectedIndex == tab.index,
                          ),
                      ],
                    )
                  : switch (AppTab.values[_selectedIndex]) {
                      AppTab.conversation =>
                        _buildConversationTab(context, isActive: true),
                      AppTab.notes => _buildNotesTab(context, isActive: true),
                      AppTab.memory => _buildMemoryTab(context, isActive: true),
                      AppTab.review => _buildReviewTab(context, isActive: true),
                      AppTab.settings =>
                        _buildSettingsTab(context, isActive: true),
                    };
              final scopedContent = AppShellLayoutScope(
                desktopWorkbench: useRail,
                child: content,
              );

              return Scaffold(
                backgroundColor: AppShellPalette.soft,
                resizeToAvoidBottomInset: false,
                body: useCollapsedShell
                    ? const SizedBox.shrink()
                    : useRail
                        ? _AppShellDesktopWorkbench(
                            selectedIndex: _selectedIndex,
                            onSelect: _selectTab,
                            child: scopedContent,
                          )
                        : ColoredBox(
                            color: AppShellPalette.soft,
                            child: MediaQuery.removePadding(
                              context: context,
                              removeTop: true,
                              child: scopedContent,
                            ),
                          ),
                bottomNavigationBar: useBottomNav
                    ? _AppShellBottomNav(
                        selectedIndex: _selectedIndex,
                        onSelect: _selectTab,
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

final class _AppShellDesktopWorkbench extends StatelessWidget {
  const _AppShellDesktopWorkbench({
    required this.selectedIndex,
    required this.onSelect,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('app_shell_desktop_workbench'),
      color: const Color(0xFFF7F9FB),
      child: Column(
        children: [
          const _AppShellDesktopTopNav(),
          Expanded(
            child: Row(
              children: [
                _AppShellDesktopSideNav(
                  selectedIndex: selectedIndex,
                  onSelect: onSelect,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _AppShellDesktopTopNav extends StatelessWidget {
  const _AppShellDesktopTopNav();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('app_shell_desktop_top_nav'),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FB),
        border: Border(bottom: BorderSide(color: Color(0xFFC6C6CD))),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                const Text(
                  'SecondLoop',
                  style: TextStyle(
                    color: Color(0xFF000000),
                    fontSize: 20,
                    height: 28 / 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 24),
                const _DesktopStatusPill(
                  label: 'Managed Pro',
                  background: Color(0xFF316BF3),
                  foreground: Color(0xFFFEFCFF),
                ),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFC6C6CD)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RuntimeSyncedDot(),
                        SizedBox(width: 6),
                        Text(
                          'Runtime Synced',
                          style: TextStyle(
                            color: Color(0xFF45464D),
                            fontSize: 11,
                            height: 14 / 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 256,
                  height: 34,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search operational vault...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF2F4F6),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFFC6C6CD)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF0051D5)),
                      ),
                    ),
                    style: const TextStyle(
                      color: Color(0xFF191C1E),
                      fontSize: 14,
                      height: 20 / 14,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: 'Sync',
                  onPressed: () {},
                  icon: const Icon(Icons.sync_rounded),
                ),
                IconButton(
                  tooltip: 'Account',
                  onPressed: () {},
                  icon: const Icon(Icons.account_circle_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _DesktopStatusPill extends StatelessWidget {
  const _DesktopStatusPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            height: 14 / 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

final class _RuntimeSyncedDot extends StatelessWidget {
  const _RuntimeSyncedDot();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 6,
      height: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

final class _AppShellDesktopSideNav extends StatelessWidget {
  const _AppShellDesktopSideNav({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const _destinations = [
    _DesktopNavDestination(
      tab: AppTab.review,
    ),
    _DesktopNavDestination(
      tab: AppTab.conversation,
    ),
    _DesktopNavDestination(
      tab: AppTab.notes,
    ),
    _DesktopNavDestination(
      tab: AppTab.memory,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FB),
        border: Border(right: BorderSide(color: Color(0xFFC6C6CD))),
      ),
      child: SizedBox(
        key: const ValueKey('app_shell_sidebar'),
        width: 256,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child: Column(
            children: [
              for (final destination in _destinations)
                _AppShellDesktopNavItem(
                  destination: destination,
                  selected: selectedIndex == destination.tab.index,
                  onTap: () => onSelect(destination.tab.index),
                ),
              const Spacer(),
              const Divider(color: Color(0xFFC6C6CD), height: 1),
              const SizedBox(height: 12),
              _AppShellDesktopNavItem(
                destination: const _DesktopNavDestination(
                  tab: AppTab.settings,
                ),
                selected: selectedIndex == AppTab.settings.index,
                onTap: () => onSelect(AppTab.settings.index),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DesktopNavDestination {
  const _DesktopNavDestination({
    required this.tab,
  });

  final AppTab tab;
}

final class _AppShellDesktopNavItem extends StatelessWidget {
  const _AppShellDesktopNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _DesktopNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = destination.tab.label(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: const Color(0xFFE6E8EA),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFECEEF0) : Colors.transparent,
              border: Border(
                right: BorderSide(
                  color:
                      selected ? const Color(0xFF0051D5) : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? destination.tab.selectedIcon
                      : destination.tab.icon,
                  size: 20,
                  color: selected
                      ? const Color(0xFF0051D5)
                      : const Color(0xFF45464D),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF0051D5)
                          : const Color(0xFF45464D),
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: 0,
                    ),
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

final class _AppShellBottomNav extends StatelessWidget {
  const _AppShellBottomNav({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('app_shell_bottom_nav'),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FB),
        border: Border(top: BorderSide(color: Color(0xFFC6C6CD))),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final tab in AppTab.values)
                Expanded(
                  child: _AppShellBottomNavItem(
                    tab: tab,
                    selected: selectedIndex == tab.index,
                    onTap: () => onSelect(tab.index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AppShellBottomNavItem extends StatelessWidget {
  const _AppShellBottomNavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? const Color(0xFFFEFCFF) : const Color(0xFF45464D);
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 14 : 8,
              vertical: selected ? 6 : 4,
            ),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF316BF3) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(size: 20, color: foreground),
                  child: tab == AppTab.settings
                      ? _AppUpdateBadgeIcon(
                          icon: selected ? tab.selectedIcon : tab.icon,
                          badgeKey: ValueKey(
                            selected
                                ? 'app_tab_settings_update_badge_bottom_nav_selected'
                                : 'app_tab_settings_update_badge_bottom_nav',
                          ),
                        )
                      : Icon(selected ? tab.selectedIcon : tab.icon),
                ),
                const SizedBox(height: 2),
                Text(
                  tab.label(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
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
