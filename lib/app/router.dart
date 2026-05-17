import 'package:flutter/material.dart';

import 'app_shell_default_pages_stub.dart'
    if (dart.library.io) 'app_shell_default_pages_io.dart'
    if (dart.library.html) 'app_shell_default_pages_web.dart'
    as app_shell_defaults;
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/quick_capture/quick_capture_scope.dart';
import '../core/update/update_badge_prefs.dart';
import '../i18n/strings.g.dart';
import '../ui/sl_surface.dart';
import '../ui/sl_tokens.dart';
import 'theme.dart';

const _kDesktopShellMaxWidth = double.infinity;
const _kDesktopShellSidebarWidth = 230.0;
const _kDesktopShellMargin = 12.0;
const _kDesktopShellRadius = 16.0;

final class _AgentShellPalette {
  const _AgentShellPalette._();

  static const blue = Color(0xFF0B5CF6);
  static const ink = Color(0xFF101936);
  static const muted = Color(0xFF63708A);
  static const line = Color(0xFFE1E7F0);
  static const panel = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF7F9FC);
  static const selected = Color(0xFFEAF1FF);
}

enum AppTab {
  conversation(Icons.chat_bubble_outline, Icons.chat_bubble),
  notes(Icons.note_alt_outlined, Icons.note_alt),
  memory(Icons.psychology_alt_outlined, Icons.psychology_alt),
  review(Icons.fact_check_outlined, Icons.fact_check),
  settings(Icons.settings_outlined, Icons.settings);

  const AppTab(this.icon, this.selectedIcon);

  static const chat = conversation;

  final IconData icon;
  final IconData selectedIcon;

  String label(BuildContext context) => switch (this) {
        AppTab.conversation => context.t.app.tabs.conversation,
        AppTab.notes => context.t.app.tabs.notes,
        AppTab.memory => context.t.app.tabs.memory,
        AppTab.review => context.t.app.tabs.review,
        AppTab.settings => context.t.app.tabs.settings,
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
          final tokens = SlTokens.of(context);
          final mediaQuery = MediaQuery.of(context);
          return LayoutBuilder(
            builder: (context, constraints) {
              final useCollapsedShell = constraints.maxHeight < 180;
              final useRail = !useCollapsedShell && constraints.maxWidth >= 720;
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

              return Scaffold(
                backgroundColor: _AgentShellPalette.soft,
                resizeToAvoidBottomInset: false,
                body: useCollapsedShell
                    ? const SizedBox.shrink()
                    : useRail
                        ? Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _kDesktopShellMaxWidth,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  _kDesktopShellMargin,
                                ),
                                child: SlSurface(
                                  key: const ValueKey(
                                    'app_shell_desktop_workspace',
                                  ),
                                  color: _AgentShellPalette.panel,
                                  borderColor: _AgentShellPalette.line,
                                  borderRadius: BorderRadius.circular(
                                    _kDesktopShellRadius,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      _kDesktopShellRadius,
                                    ),
                                    child: Row(
                                      children: [
                                        _AppShellSidebar(
                                          selectedIndex: _selectedIndex,
                                          onSelect: _selectTab,
                                        ),
                                        const _AppShellDivider(),
                                        Expanded(child: content),
                                      ],
                                    ),
                                  ),
                                ),
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
                              borderRadius:
                                  BorderRadius.circular(tokens.radiusLg),
                              child: MediaQuery.removePadding(
                                context: context,
                                removeTop: true,
                                child: content,
                              ),
                            ),
                          ),
                bottomNavigationBar: useBottomNav
                    ? NavigationBar(
                        key: const ValueKey('app_shell_bottom_nav'),
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _selectTab,
                        destinations: [
                          for (final t in AppTab.values)
                            NavigationDestination(
                              icon: t == AppTab.settings
                                  ? _AppUpdateBadgeIcon(
                                      icon: t.icon,
                                      badgeKey: const ValueKey(
                                        'app_tab_settings_update_badge_bottom_nav',
                                      ),
                                    )
                                  : Icon(t.icon),
                              selectedIcon: t == AppTab.settings
                                  ? _AppUpdateBadgeIcon(
                                      icon: t.selectedIcon,
                                      badgeKey: const ValueKey(
                                        'app_tab_settings_update_badge_bottom_nav_selected',
                                      ),
                                    )
                                  : Icon(t.selectedIcon),
                              label: t.label(context),
                            ),
                        ],
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

final class _AppShellSidebar extends StatelessWidget {
  const _AppShellSidebar({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('app_shell_sidebar'),
      width: _kDesktopShellSidebarWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 30, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AppShellBrand(),
            const SizedBox(height: 42),
            for (final tab in AppTab.values) ...[
              _AppShellNavItem(
                tab: tab,
                selected: selectedIndex == tab.index,
                onTap: () => onSelect(tab.index),
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

final class _AppShellBrand extends StatelessWidget {
  const _AppShellBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.all_inclusive_rounded,
          color: _AgentShellPalette.blue,
          size: 34,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.t.app.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _AgentShellPalette.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

final class _AppShellNavItem extends StatelessWidget {
  const _AppShellNavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = tab.label(context);
    final iconColor =
        selected ? _AgentShellPalette.blue : _AgentShellPalette.muted;
    final textColor =
        selected ? _AgentShellPalette.blue : _AgentShellPalette.ink;
    final icon = selected ? tab.selectedIcon : tab.icon;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('app_shell_nav_${tab.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: _AgentShellPalette.selected.withOpacity(0.52),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color:
                  selected ? _AgentShellPalette.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                IconTheme(
                  data: IconThemeData(color: iconColor, size: 24),
                  child: tab == AppTab.settings
                      ? _AppUpdateBadgeIcon(
                          icon: icon,
                          badgeKey: ValueKey(
                            selected
                                ? 'app_tab_settings_update_badge_selected'
                                : 'app_tab_settings_update_badge',
                          ),
                        )
                      : Icon(icon),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _AppShellDivider extends StatelessWidget {
  const _AppShellDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 1,
      child: ColoredBox(color: _AgentShellPalette.line),
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
