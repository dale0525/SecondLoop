part of 'settings_page.dart';

extension _SettingsPageTheme on _SettingsPageState {
  String _themeModeLabel(BuildContext context, ThemeMode mode) {
    final t = context.t;
    return switch (mode) {
      ThemeMode.system => t.settings.theme.options.system,
      ThemeMode.light => t.settings.theme.options.light,
      ThemeMode.dark => t.settings.theme.options.dark,
    };
  }

  String _themePaletteTitle(BuildContext context) {
    return context.t.settings.theme.styleTitle;
  }

  String _themePaletteSubtitle(BuildContext context) {
    return context.t.settings.theme.styleSubtitle;
  }

  String _themePaletteDialogTitle(BuildContext context) {
    return context.t.settings.theme.styleDialogTitle;
  }

  String _themePaletteLabel(BuildContext context, AppThemePalette palette) {
    final options = context.t.settings.theme.styleOptions;
    return switch (palette) {
      AppThemePalette.studio => options.studio,
      AppThemePalette.forest => options.forest,
      AppThemePalette.ocean => options.ocean,
      AppThemePalette.sunset => options.sunset,
      AppThemePalette.monochrome => options.monochrome,
    };
  }

  Future<void> _selectThemeMode() async {
    if (_busy) return;

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
                title: Text(t.settings.theme.options.system),
                value: ThemeMode.system,
                groupValue: current,
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
              RadioListTile<ThemeMode>(
                title: Text(t.settings.theme.options.light),
                value: ThemeMode.light,
                groupValue: current,
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
              RadioListTile<ThemeMode>(
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

    if (!mounted) return;
    final current = AppThemeModePrefs.value.value;
    if (selected == null || selected == current) return;

    await AppThemeModePrefs.setThemeMode(selected);
  }

  Future<void> _selectThemePalette() async {
    if (_busy) return;

    final selected = await showDialog<AppThemePalette>(
      context: context,
      builder: (context) {
        final t = context.t;
        final current = AppThemePalettePrefs.value.value;
        return AlertDialog(
          title: Text(_themePaletteDialogTitle(context)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final palette in AppThemePalette.values)
                RadioListTile<AppThemePalette>(
                  title: Text(_themePaletteLabel(context, palette)),
                  value: palette,
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

    if (!mounted) return;
    final current = AppThemePalettePrefs.value.value;
    if (selected == null || selected == current) return;

    await AppThemePalettePrefs.setPalette(selected);
  }
}
