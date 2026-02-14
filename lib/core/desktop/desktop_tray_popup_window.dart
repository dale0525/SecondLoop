import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/sl_surface.dart';
import 'desktop_tray_menu_controller.dart' show DesktopTrayProUsage;

final class DesktopTrayPopupLabels {
  const DesktopTrayPopupLabels({
    required this.title,
    required this.open,
    required this.settings,
    required this.startWithSystem,
    required this.quit,
    required this.signedIn,
    required this.aiUsage,
    required this.storageUsage,
  });

  final String title;
  final String open;
  final String settings;
  final String startWithSystem;
  final String quit;
  final String signedIn;
  final String aiUsage;
  final String storageUsage;
}

class DesktopTrayPopupWindow extends StatefulWidget {
  const DesktopTrayPopupWindow({
    required this.labels,
    required this.proUsage,
    required this.startWithSystemEnabled,
    required this.refreshingUsage,
    required this.onOpenWindow,
    required this.onOpenSettings,
    required this.onToggleStartWithSystem,
    required this.onQuit,
    super.key,
  });

  final DesktopTrayPopupLabels labels;
  final DesktopTrayProUsage? proUsage;
  final bool startWithSystemEnabled;
  final bool refreshingUsage;

  final Future<void> Function() onOpenWindow;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function(bool enabled) onToggleStartWithSystem;
  final Future<void> Function() onQuit;

  @override
  State<DesktopTrayPopupWindow> createState() => _DesktopTrayPopupWindowState();
}

class _DesktopTrayPopupWindowState extends State<DesktopTrayPopupWindow> {
  bool _busy = false;

  Future<void> _invoke(Future<void> Function() action) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.scrim.withOpacity(0.05),
      child: SafeArea(
        minimum: const EdgeInsets.all(6),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 236,
              maxWidth: 276,
            ),
            child: SlSurface(
              borderRadius: BorderRadius.circular(12),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.labels.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.proUsage != null)
                        _ProUsageBlock(
                          labels: widget.labels,
                          usage: widget.proUsage!,
                          refreshingUsage: widget.refreshingUsage,
                        ),
                      const SizedBox(height: 4),
                      _CompactActionTile(
                        icon: Icons.home_outlined,
                        title: widget.labels.open,
                        enabled: !_busy,
                        onTap: () {
                          unawaited(_invoke(widget.onOpenWindow));
                        },
                      ),
                      _CompactActionTile(
                        icon: Icons.settings_outlined,
                        title: widget.labels.settings,
                        enabled: !_busy,
                        onTap: () {
                          unawaited(_invoke(widget.onOpenSettings));
                        },
                      ),
                      _CompactSwitchTile(
                        icon: Icons.rocket_launch_outlined,
                        title: widget.labels.startWithSystem,
                        value: widget.startWithSystemEnabled,
                        enabled: !_busy,
                        onChanged: (enabled) {
                          unawaited(
                            _invoke(
                              () => widget.onToggleStartWithSystem(enabled),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 8, thickness: 0.8),
                      _CompactActionTile(
                        icon: Icons.power_settings_new,
                        title: widget.labels.quit,
                        enabled: !_busy,
                        iconColor: theme.colorScheme.error,
                        textColor: theme.colorScheme.error,
                        onTap: () {
                          unawaited(_invoke(widget.onQuit));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactActionTile extends StatelessWidget {
  const _CompactActionTile({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  final IconData icon;
  final String title;
  final bool enabled;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hoverColor = theme.colorScheme.primary.withOpacity(0.08);

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      horizontalTitleGap: 8,
      minVerticalPadding: 0,
      minLeadingWidth: 20,
      minTileHeight: 34,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: hoverColor,
      splashColor: hoverColor,
      leading: Icon(icon, size: 16, color: iconColor),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class _CompactSwitchTile extends StatelessWidget {
  const _CompactSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hoverColor = theme.colorScheme.primary.withOpacity(0.08);

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      horizontalTitleGap: 8,
      minVerticalPadding: 0,
      minLeadingWidth: 20,
      minTileHeight: 34,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: hoverColor,
      splashColor: hoverColor,
      leading: Icon(icon, size: 16),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: SizedBox(
        width: 38,
        child: Transform.scale(
          alignment: Alignment.centerRight,
          scale: 0.78,
          child: Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }
}

class _ProUsageBlock extends StatelessWidget {
  const _ProUsageBlock({
    required this.labels,
    required this.usage,
    required this.refreshingUsage,
  });

  final DesktopTrayPopupLabels labels;
  final DesktopTrayProUsage usage;
  final bool refreshingUsage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedInLabel = '${labels.signedIn}: ${usage.email}';

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.24),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  signedInLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (refreshingUsage)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 7),
          _UsageProgressRow(
            title: labels.aiUsage,
            percent: usage.aiUsagePercent,
          ),
          const SizedBox(height: 5),
          _UsageProgressRow(
            title: labels.storageUsage,
            percent: usage.storageUsagePercent,
          ),
        ],
      ),
    );
  }
}

class _UsageProgressRow extends StatelessWidget {
  const _UsageProgressRow({required this.title, required this.percent});

  final String title;
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = percent?.clamp(0, 100);
    final label = clamped == null ? '--%' : '$clamped%';
    final value = clamped == null ? 0.0 : clamped / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: value, minHeight: 4.5),
        ),
      ],
    );
  }
}
