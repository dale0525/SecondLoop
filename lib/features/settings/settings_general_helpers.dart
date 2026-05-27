import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/desktop/desktop_quick_capture_hotkey_prefs.dart';
import '../../core/desktop/system_hotkey_conflicts.dart';
import '../../core/desktop/system_hotkey_recorder.dart';
import '../../i18n/strings.g.dart';

String settingsLocaleLabel(BuildContext context, AppLocale locale) {
  return switch (locale) {
    AppLocale.en => context.t.settings.language.options.en,
    AppLocale.zhCn => context.t.settings.language.options.zhCn,
  };
}

String currentSettingsLanguageLabel(
  BuildContext context,
  AppLocale? localeOverride,
) {
  if (localeOverride == null) {
    final deviceLocale = AppLocaleUtils.findDeviceLocale();
    return context.t.settings.language.options.systemWithValue(
      value: settingsLocaleLabel(context, deviceLocale),
    );
  }
  return settingsLocaleLabel(context, localeOverride);
}

Future<AppLocale?> selectSettingsLanguageOverride(
  BuildContext context,
  AppLocale? current,
) {
  return showDialog<AppLocale?>(
    context: context,
    builder: (context) {
      final t = context.t;
      return AlertDialog(
        title: Text(t.settings.language.dialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AppLocale?>(
              title: Text(t.settings.language.options.system),
              value: null,
              groupValue: current,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
            RadioListTile<AppLocale?>(
              title: Text(t.settings.language.options.en),
              value: AppLocale.en,
              groupValue: current,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
            RadioListTile<AppLocale?>(
              title: Text(t.settings.language.options.zhCn),
              value: AppLocale.zhCn,
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
}

HotKey defaultSettingsQuickCaptureHotKey(TargetPlatform platform) {
  return HotKey(
    identifier: DesktopQuickCaptureHotkeyPrefs.hotKeyIdentifier,
    key: PhysicalKeyboardKey.keyK,
    modifiers: [
      if (platform == TargetPlatform.macOS)
        HotKeyModifier.meta
      else
        HotKeyModifier.control,
      HotKeyModifier.shift,
    ],
    scope: HotKeyScope.system,
  );
}

String formatSettingsHotKey(HotKey hotKey, TargetPlatform platform) {
  final pieces = [
    for (final HotKeyModifier modifier in hotKey.modifiers ?? const [])
      switch (modifier) {
        HotKeyModifier.meta => platform == TargetPlatform.macOS ? '⌘' : 'Win',
        HotKeyModifier.control =>
          platform == TargetPlatform.macOS ? '⌃' : 'Ctrl',
        HotKeyModifier.shift =>
          platform == TargetPlatform.macOS ? '⇧' : 'Shift',
        HotKeyModifier.alt => platform == TargetPlatform.macOS ? '⌥' : 'Alt',
        HotKeyModifier.capsLock => 'Caps',
        HotKeyModifier.fn => 'Fn',
      },
    _hotKeyKeyLabel(hotKey),
  ];
  return platform == TargetPlatform.macOS ? pieces.join() : pieces.join(' + ');
}

String? settingsQuickCaptureHotkeyError(
  BuildContext context,
  HotKey hotKey,
  TargetPlatform platform,
) {
  final t = context.t.settings.quickCaptureHotkey;

  final modifiers = hotKey.modifiers ?? [];
  if (modifiers.isEmpty) return t.validation.missingModifier;

  final isModifierKey = HotKeyModifier.values.any(
    (modifier) => modifier.physicalKeys.contains(hotKey.physicalKey),
  );
  if (isModifierKey) return t.validation.modifierOnly;

  final conflict = systemHotkeyConflict(
    hotKey: hotKey,
    platform: platform,
  );
  if (conflict != null) {
    return t.validation.systemConflict(
      name: _systemHotkeyConflictName(context, conflict),
    );
  }

  return null;
}

Future<void> editSettingsQuickCaptureHotkey(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final t = context.t;

  await DesktopQuickCaptureHotkeyPrefs.load();
  if (!context.mounted) return;

  final platform = defaultTargetPlatform;
  final defaultHotKey = defaultSettingsQuickCaptureHotKey(platform);
  final existing = DesktopQuickCaptureHotkeyPrefs.value.value ?? defaultHotKey;

  HotKey draft = existing;
  String? error = settingsQuickCaptureHotkeyError(context, draft, platform);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void onRecorded(HotKey hotKey) {
            setDialogState(() {
              draft = hotKey;
              error = settingsQuickCaptureHotkeyError(
                dialogContext,
                draft,
                platform,
              );
            });
          }

          return AlertDialog(
            title: Text(t.settings.quickCaptureHotkey.dialogTitle),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.settings.quickCaptureHotkey.dialogBody),
                  const SizedBox(height: 12),
                  Focus(
                    autofocus: true,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(dialogContext).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatSettingsHotKey(draft, platform),
                              style:
                                  Theme.of(dialogContext).textTheme.titleMedium,
                            ),
                          ),
                          Offstage(
                            offstage: true,
                            child: SystemHotKeyRecorder(
                              initialHotKey: draft,
                              onHotKeyRecorded: onRecorded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(t.common.actions.cancel),
              ),
              TextButton(
                onPressed: () async {
                  await DesktopQuickCaptureHotkeyPrefs.clear();
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(t.settings.quickCaptureHotkey.saved),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(t.settings.quickCaptureHotkey.actions.resetDefault),
              ),
              FilledButton(
                onPressed: error == null
                    ? () async {
                        await DesktopQuickCaptureHotkeyPrefs.setHotKey(draft);
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(t.settings.quickCaptureHotkey.saved),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    : null,
                child: Text(t.common.actions.save),
              ),
            ],
          );
        },
      );
    },
  );
}

String _hotKeyKeyLabel(HotKey hotKey) {
  final keyLabel = hotKey.logicalKey.keyLabel;
  if (keyLabel.trim().isNotEmpty) {
    return keyLabel.length == 1 ? keyLabel.toUpperCase() : keyLabel;
  }

  final debugName = hotKey.physicalKey.debugName ?? 'Unknown';
  return debugName.replaceFirst('Key ', '').replaceFirst('Digit ', '').trim();
}

String _systemHotkeyConflictName(
  BuildContext context,
  SystemHotkeyConflict conflict,
) {
  final t = context.t.settings.quickCaptureHotkey.conflicts;
  return switch (conflict) {
    SystemHotkeyConflict.macosSpotlight => t.macosSpotlight,
    SystemHotkeyConflict.macosFinderSearch => t.macosFinderSearch,
    SystemHotkeyConflict.macosInputSourceSwitch => t.macosInputSourceSwitch,
    SystemHotkeyConflict.macosEmojiPicker => t.macosEmojiPicker,
    SystemHotkeyConflict.macosScreenshot => t.macosScreenshot,
    SystemHotkeyConflict.macosAppSwitcher => t.macosAppSwitcher,
    SystemHotkeyConflict.macosForceQuit => t.macosForceQuit,
    SystemHotkeyConflict.macosLockScreen => t.macosLockScreen,
    SystemHotkeyConflict.windowsLock => t.windowsLock,
    SystemHotkeyConflict.windowsShowDesktop => t.windowsShowDesktop,
    SystemHotkeyConflict.windowsFileExplorer => t.windowsFileExplorer,
    SystemHotkeyConflict.windowsRun => t.windowsRun,
    SystemHotkeyConflict.windowsSearch => t.windowsSearch,
    SystemHotkeyConflict.windowsSettings => t.windowsSettings,
    SystemHotkeyConflict.windowsTaskView => t.windowsTaskView,
    SystemHotkeyConflict.windowsLanguageSwitch => t.windowsLanguageSwitch,
    SystemHotkeyConflict.windowsAppSwitcher => t.windowsAppSwitcher,
  };
}
