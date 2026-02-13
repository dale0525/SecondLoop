import 'package:menu_base/menu_base.dart';

const kDesktopTrayMenuOpenKey = 'tray_open';
const kDesktopTrayMenuHideKey = 'tray_hide';
const kDesktopTrayMenuSettingsKey = 'tray_settings';
const kDesktopTrayMenuStartWithSystemKey = 'tray_start_with_system';
const kDesktopTrayMenuQuitKey = 'tray_quit';

String formatTrayUsageProgress(int? percent) {
  if (percent == null) {
    return '[----------] --%';
  }

  final clamped = percent.clamp(0, 100);
  final filled = ((clamped / 10).round()).clamp(0, 10);
  final bar = '${'#' * filled}${'-' * (10 - filled)}';
  return '[$bar] $clamped%';
}

final class DesktopTrayMenuLabels {
  const DesktopTrayMenuLabels({
    required this.open,
    required this.hide,
    required this.settings,
    required this.startWithSystem,
    required this.quit,
    required this.signedIn,
    required this.aiUsage,
    required this.storageUsage,
  });

  final String open;
  final String hide;
  final String settings;
  final String startWithSystem;
  final String quit;
  final String signedIn;
  final String aiUsage;
  final String storageUsage;
}

final class DesktopTrayProUsage {
  const DesktopTrayProUsage({
    required this.email,
    required this.aiUsagePercent,
    required this.storageUsagePercent,
  });

  final String email;
  final int? aiUsagePercent;
  final int? storageUsagePercent;

  @override
  bool operator ==(Object other) {
    return other is DesktopTrayProUsage &&
        other.email == email &&
        other.aiUsagePercent == aiUsagePercent &&
        other.storageUsagePercent == storageUsagePercent;
  }

  @override
  int get hashCode => Object.hash(email, aiUsagePercent, storageUsagePercent);
}

final class DesktopTrayMenuState {
  const DesktopTrayMenuState({
    required this.startWithSystemEnabled,
    this.proUsage,
  });

  final bool startWithSystemEnabled;
  final DesktopTrayProUsage? proUsage;
}

final class DesktopTrayMenuController {
  DesktopTrayMenuController({
    required this.onOpenWindow,
    required this.onHideWindow,
    required this.onOpenSettings,
    required this.onToggleStartWithSystem,
    required this.onQuit,
  });

  final Future<void> Function() onOpenWindow;
  final Future<void> Function() onHideWindow;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function(bool enabled) onToggleStartWithSystem;
  final Future<void> Function() onQuit;

  Menu buildMenu({
    required DesktopTrayMenuLabels labels,
    required DesktopTrayMenuState state,
  }) {
    final items = <MenuItem>[];
    final proUsage = state.proUsage;

    if (proUsage != null) {
      items.add(
        MenuItem(
          label: '${labels.signedIn}: ${proUsage.email}',
          disabled: true,
        ),
      );
      items.add(
        MenuItem(
          label:
              '${labels.aiUsage} ${formatTrayUsageProgress(proUsage.aiUsagePercent)}',
          disabled: true,
        ),
      );
      items.add(
        MenuItem(
          label:
              '${labels.storageUsage} ${formatTrayUsageProgress(proUsage.storageUsagePercent)}',
          disabled: true,
        ),
      );
      items.add(MenuItem.separator());
    }

    items.add(MenuItem(key: kDesktopTrayMenuOpenKey, label: labels.open));
    items.add(MenuItem(key: kDesktopTrayMenuHideKey, label: labels.hide));
    items.add(
      MenuItem(key: kDesktopTrayMenuSettingsKey, label: labels.settings),
    );
    items.add(
      MenuItem.checkbox(
        key: kDesktopTrayMenuStartWithSystemKey,
        label: labels.startWithSystem,
        checked: state.startWithSystemEnabled,
      ),
    );
    items.add(MenuItem.separator());
    items.add(MenuItem(key: kDesktopTrayMenuQuitKey, label: labels.quit));

    return Menu(items: items);
  }

  Future<void> onMenuItemClick(
    MenuItem menuItem, {
    required bool startWithSystemEnabled,
  }) async {
    switch (menuItem.key) {
      case kDesktopTrayMenuOpenKey:
        await onOpenWindow();
        break;
      case kDesktopTrayMenuHideKey:
        await onHideWindow();
        break;
      case kDesktopTrayMenuSettingsKey:
        await onOpenSettings();
        break;
      case kDesktopTrayMenuStartWithSystemKey:
        await onToggleStartWithSystem(!startWithSystemEnabled);
        break;
      case kDesktopTrayMenuQuitKey:
        await onQuit();
        break;
    }
  }
}
