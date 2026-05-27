import 'package:flutter/material.dart';

import '../../app/theme_mode_prefs.dart';
import '../../i18n/strings.g.dart';
import 'settings_ui.dart';

class SettingsThemeModeRow extends StatelessWidget {
  const SettingsThemeModeRow({
    super.key,
    this.enabled = true,
  });

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: key ?? const ValueKey('settings_theme_mode'),
      leading: const Icon(Icons.contrast_rounded),
      title: context.t.settings.theme.title,
      body: context.t.settings.theme.subtitle,
      trailing: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeModePrefs.value,
        builder: (context, mode, child) {
          return Text(settingsThemeModeLabel(context, mode));
        },
      ),
      showChevron: true,
      enabled: enabled,
      onTap: enabled ? () => selectSettingsThemeMode(context) : null,
    );
  }
}

String settingsThemeModeLabel(BuildContext context, ThemeMode mode) {
  final t = context.t;
  return switch (mode) {
    ThemeMode.system => t.settings.theme.options.system,
    ThemeMode.light => t.settings.theme.options.light,
    ThemeMode.dark => t.settings.theme.options.dark,
  };
}

Future<void> selectSettingsThemeMode(BuildContext context) async {
  final selected = await showDialog<ThemeMode>(
    context: context,
    builder: (context) {
      final t = context.t;
      final current = AppThemeModePrefs.value.value;
      return AlertDialog(
        title: Text(t.settings.theme.dialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              key: const ValueKey('settings_theme_mode_option_system'),
              title: Text(t.settings.theme.options.system),
              value: ThemeMode.system,
              groupValue: current,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
            RadioListTile<ThemeMode>(
              key: const ValueKey('settings_theme_mode_option_light'),
              title: Text(t.settings.theme.options.light),
              value: ThemeMode.light,
              groupValue: current,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
            RadioListTile<ThemeMode>(
              key: const ValueKey('settings_theme_mode_option_dark'),
              title: Text(t.settings.theme.options.dark),
              value: ThemeMode.dark,
              groupValue: current,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(current),
            child: Text(t.common.actions.cancel),
          ),
        ],
      );
    },
  );

  final current = AppThemeModePrefs.value.value;
  if (selected == null || selected == current) return;

  await AppThemeModePrefs.setThemeMode(selected);
}
