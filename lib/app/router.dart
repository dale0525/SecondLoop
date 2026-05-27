import 'package:flutter/material.dart';

import 'app_shell_default_pages_stub.dart'
    if (dart.library.io) 'app_shell_default_pages_io.dart'
    if (dart.library.html) 'app_shell_default_pages_web.dart'
    as app_shell_defaults;
import '../core/quick_capture/quick_capture_controller.dart';
import '../core/quick_capture/quick_capture_scope.dart';
import '../core/update/update_badge_prefs.dart';
import '../features/agent_ui/desktop_approvals_workbench_page.dart';
import '../features/agent_ui/desktop_connectors_workbench_page.dart';
import '../features/agent_ui/desktop_memory_workbench_page.dart';
import 'app_shell_runtime_status_pill.dart';
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

  String get navKey => switch (this) {
        AppTab.review => 'app_shell_nav_review',
        AppTab.conversation => 'app_shell_nav_conversation',
        AppTab.notes => 'app_shell_nav_notes',
        AppTab.memory => 'app_shell_nav_memory',
        AppTab.settings => 'app_shell_nav_settings',
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
    this.desktopMemoryBuilder,
    this.desktopApprovalsBuilder,
    this.desktopConnectorsBuilder,
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
  final Widget Function(BuildContext context, bool isActive)?
      desktopMemoryBuilder;
  final Widget Function(BuildContext context, bool isActive)?
      desktopApprovalsBuilder;
  final Widget Function(BuildContext context, bool isActive)?
      desktopConnectorsBuilder;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex = widget.initialTab.index;
  late final Set<int> _loadedIndexes = <int>{_selectedIndex};
  _DesktopNavAction? _selectedDesktopAction;
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
      _selectedDesktopAction = null;
    }
  }

  void _selectTab(int index) {
    if (_selectedIndex == index && _selectedDesktopAction == null) return;
    setState(() {
      _selectedIndex = index;
      _loadedIndexes.add(index);
      _selectedDesktopAction = null;
    });
  }

  void _selectDesktopAction(_DesktopNavAction action) {
    if (_selectedDesktopAction == action) return;
    setState(() {
      _selectedDesktopAction = action;
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

  Widget _buildDesktopAction(
    BuildContext context,
    _DesktopNavAction action, {
    required bool isActive,
  }) {
    switch (action) {
      case _DesktopNavAction.memory:
        final builder = widget.desktopMemoryBuilder;
        if (builder != null) return builder(context, isActive);
        return const DesktopMemoryWorkbenchPage();
      case _DesktopNavAction.approvals:
        final builder = widget.desktopApprovalsBuilder;
        if (builder != null) return builder(context, isActive);
        return const DesktopApprovalsWorkbenchPage();
      case _DesktopNavAction.connectors:
        final builder = widget.desktopConnectorsBuilder;
        if (builder != null) return builder(context, isActive);
        return DesktopConnectorsWorkbenchPage(
          onOpenSettings: () => _selectTab(AppTab.settings.index),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final shellTheme = parentTheme.brightness == Brightness.dark
        ? AppTheme.dark(locale: locale, platform: parentTheme.platform)
        : AppTheme.light(locale: locale, platform: parentTheme.platform);
    return Theme(
      data: shellTheme,
      child: Builder(
        builder: (context) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final colors = _AppShellChromeColors.of(context);
              final useCollapsedShell = constraints.maxHeight < 180;
              final useRail = !useCollapsedShell && constraints.maxWidth >= 960;
              final useBottomNav = !useCollapsedShell && !useRail;
              final tabContent = useRail || useBottomNav
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
              final desktopAction = useRail ? _selectedDesktopAction : null;
              final content = desktopAction == null
                  ? tabContent
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Offstage(
                          offstage: true,
                          child: tabContent,
                        ),
                        _buildDesktopAction(
                          context,
                          desktopAction,
                          isActive: true,
                        ),
                      ],
                    );
              final scopedContent = AppShellLayoutScope(
                desktopWorkbench: useRail,
                child: content,
              );

              return Scaffold(
                backgroundColor: colors.background,
                resizeToAvoidBottomInset: false,
                body: useCollapsedShell
                    ? const SizedBox.shrink()
                    : useRail
                        ? _AppShellDesktopWorkbench(
                            selectedIndex: _selectedIndex,
                            selectedDesktopAction: _selectedDesktopAction,
                            onSelect: _selectTab,
                            onSelectDesktopAction: _selectDesktopAction,
                            child: scopedContent,
                          )
                        : ColoredBox(
                            color: colors.background,
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
    required this.selectedDesktopAction,
    required this.onSelect,
    required this.onSelectDesktopAction,
    required this.child,
  });

  final int selectedIndex;
  final _DesktopNavAction? selectedDesktopAction;
  final ValueChanged<int> onSelect;
  final ValueChanged<_DesktopNavAction> onSelectDesktopAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = _AppShellChromeColors.of(context);
    return ColoredBox(
      key: const ValueKey('app_shell_desktop_workbench'),
      color: colors.background,
      child: Stack(
        children: [
          Column(
            children: [
              const _AppShellDesktopTopNav(),
              Expanded(
                child: Row(
                  children: [
                    _AppShellDesktopSideNav(
                      selectedIndex: selectedIndex,
                      selectedDesktopAction: selectedDesktopAction,
                      onSelect: onSelect,
                      onSelectDesktopAction: onSelectDesktopAction,
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
          const Positioned(
            right: 32,
            bottom: 32,
            child: _AppShellDesktopQuickCaptureButton(),
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
    final colors = _AppShellChromeColors.of(context);
    return DecoratedBox(
      key: const ValueKey('app_shell_desktop_top_nav'),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Text(
                  'SecondLoop',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    height: 28 / 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 24),
                const AppShellRuntimeStatusPill(),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _RuntimeSyncedDot(),
                        const SizedBox(width: 6),
                        Text(
                          'Runtime Synced',
                          style: TextStyle(
                            color: colors.muted,
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
                    key: const ValueKey('app_shell_desktop_vault_search'),
                    readOnly: true,
                    onTap: () => _showDesktopWorkbenchSnack(
                      context,
                      'Operational vault search needs runtime search configuration. (tool_unavailable)',
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search operational vault...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: colors.field,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: colors.accent),
                      ),
                    ),
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 14,
                      height: 20 / 14,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: 'Sync',
                  onPressed: () => _showDesktopWorkbenchSnack(
                    context,
                    'Runtime sync follows the active runtime connection.',
                  ),
                  icon: const Icon(Icons.sync_rounded),
                ),
                IconButton(
                  tooltip: 'Account',
                  onPressed: () => _showDesktopWorkbenchSnack(
                    context,
                    'Account controls are available from Settings.',
                  ),
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

final class _AppShellChromeColors {
  const _AppShellChromeColors({
    required this.background,
    required this.field,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.selected,
    required this.hover,
    required this.quickCaptureBackground,
    required this.quickCaptureForeground,
  });

  final Color background;
  final Color field;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color selected;
  final Color hover;
  final Color quickCaptureBackground;
  final Color quickCaptureForeground;

  static _AppShellChromeColors of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const _AppShellChromeColors(
        background: AppShellPalette.darkSoft,
        field: AppShellPalette.darkSurface,
        border: AppShellPalette.darkLine,
        text: AppShellPalette.darkInk,
        muted: AppShellPalette.darkMuted,
        accent: AppShellPalette.darkBlue,
        onAccent: Color(0xFF061A33),
        selected: AppShellPalette.darkSelected,
        hover: AppShellPalette.darkSurface,
        quickCaptureBackground: AppShellPalette.darkBlue,
        quickCaptureForeground: Color(0xFF061A33),
      );
    }
    return const _AppShellChromeColors(
      background: AppShellPalette.soft,
      field: Color(0xFFF2F4F6),
      border: Color(0xFFC6C6CD),
      text: Color(0xFF000000),
      muted: Color(0xFF45464D),
      accent: Color(0xFF0051D5),
      onAccent: Color(0xFFFEFCFF),
      selected: Color(0xFFECEEF0),
      hover: Color(0xFFE6E8EA),
      quickCaptureBackground: Color(0xFF000000),
      quickCaptureForeground: Color(0xFFFFFFFF),
    );
  }
}

final class _AppShellDesktopSideNav extends StatelessWidget {
  const _AppShellDesktopSideNav({
    required this.selectedIndex,
    required this.selectedDesktopAction,
    required this.onSelect,
    required this.onSelectDesktopAction,
  });

  final int selectedIndex;
  final _DesktopNavAction? selectedDesktopAction;
  final ValueChanged<int> onSelect;
  final ValueChanged<_DesktopNavAction> onSelectDesktopAction;

  static const _destinations = [
    _DesktopNavDestination.tab(AppTab.review),
    _DesktopNavDestination.tab(AppTab.conversation),
    _DesktopNavDestination.tab(AppTab.notes),
    _DesktopNavDestination.tab(AppTab.memory),
    _DesktopNavDestination.action(
      label: 'Memory',
      icon: Icons.psychology_outlined,
      selectedIcon: Icons.psychology,
      action: _DesktopNavAction.memory,
    ),
    _DesktopNavDestination.action(
      label: 'Approvals',
      icon: Icons.rule_outlined,
      selectedIcon: Icons.rule,
      action: _DesktopNavAction.approvals,
    ),
    _DesktopNavDestination.action(
      label: 'Connectors',
      icon: Icons.hub_outlined,
      selectedIcon: Icons.hub,
      action: _DesktopNavAction.connectors,
    ),
  ];

  void _activateDestination(
    BuildContext context,
    _DesktopNavDestination destination,
  ) {
    final tab = destination.tab;
    if (tab != null) {
      onSelect(tab.index);
      return;
    }
    switch (destination.action) {
      case _DesktopNavAction.memory:
        onSelectDesktopAction(_DesktopNavAction.memory);
        break;
      case _DesktopNavAction.approvals:
        onSelectDesktopAction(_DesktopNavAction.approvals);
        break;
      case _DesktopNavAction.connectors:
        onSelectDesktopAction(_DesktopNavAction.connectors);
        break;
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _AppShellChromeColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(right: BorderSide(color: colors.border)),
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
                  selected: destination.tab != null
                      ? selectedDesktopAction == null &&
                          selectedIndex == destination.tab!.index
                      : selectedDesktopAction == destination.action,
                  onTap: () => _activateDestination(context, destination),
                ),
              const Spacer(),
              Divider(color: colors.border, height: 1),
              const SizedBox(height: 12),
              _AppShellDesktopNavItem(
                destination: const _DesktopNavDestination.tab(AppTab.settings),
                selected: selectedDesktopAction == null &&
                    selectedIndex == AppTab.settings.index,
                onTap: () => onSelect(AppTab.settings.index),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DesktopNavAction { memory, approvals, connectors }

final class _DesktopNavDestination {
  const _DesktopNavDestination.tab(this.tab)
      : label = null,
        icon = null,
        selectedIcon = null,
        action = null;

  const _DesktopNavDestination.action({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.action,
  }) : tab = null;

  final AppTab? tab;
  final String? label;
  final IconData? icon;
  final IconData? selectedIcon;
  final _DesktopNavAction? action;

  String resolvedLabel(BuildContext context) => tab?.label(context) ?? label!;

  IconData resolvedIcon({required bool selected}) {
    final tab = this.tab;
    if (tab != null) return selected ? tab.selectedIcon : tab.icon;
    return selected ? selectedIcon! : icon!;
  }

  String get navKey {
    final tab = this.tab;
    if (tab != null) return tab.navKey;
    return switch (action) {
      _DesktopNavAction.memory => 'app_shell_nav_desktop_memory',
      _DesktopNavAction.approvals => 'app_shell_nav_desktop_approvals',
      _DesktopNavAction.connectors => 'app_shell_nav_desktop_connectors',
      null => 'app_shell_nav_unknown',
    };
  }
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
    final label = destination.resolvedLabel(context);
    final colors = _AppShellChromeColors.of(context);
    return Semantics(
      key: ValueKey(destination.navKey),
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.hover,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: selected ? colors.selected : Colors.transparent,
              border: Border(
                right: BorderSide(
                  color: selected ? colors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  destination.resolvedIcon(selected: selected),
                  size: 20,
                  color: selected ? colors.accent : colors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? colors.accent : colors.muted,
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

final class _AppShellDesktopQuickCaptureButton extends StatelessWidget {
  const _AppShellDesktopQuickCaptureButton();

  @override
  Widget build(BuildContext context) {
    final colors = _AppShellChromeColors.of(context);
    return SizedBox.square(
      key: const ValueKey('app_shell_desktop_quick_capture'),
      dimension: 56,
      child: FloatingActionButton(
        tooltip: 'Quick Capture',
        backgroundColor: colors.quickCaptureBackground,
        foregroundColor: colors.quickCaptureForeground,
        onPressed: () {
          final controller = QuickCaptureScope.maybeOf(context);
          if (controller != null) {
            controller.show();
            return;
          }
          _showDesktopWorkbenchSnack(
            context,
            'Quick Capture is unavailable in this context. (tool_unavailable)',
          );
        },
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}

void _showDesktopWorkbenchSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
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
    final colors = _AppShellChromeColors.of(context);
    return DecoratedBox(
      key: const ValueKey('app_shell_bottom_nav'),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
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
    final colors = _AppShellChromeColors.of(context);
    final foreground = selected ? colors.onAccent : colors.muted;
    return Semantics(
      key: ValueKey(tab.navKey),
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
              color: selected ? colors.accent : Colors.transparent,
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
