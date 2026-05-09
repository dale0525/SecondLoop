import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme_palette_prefs.dart';
import '../../app/theme_mode_prefs.dart';
import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_access.dart';
import '../../core/cloud/cloud_auth_controller.dart';
import '../../core/notifications/review_reminder_in_app_fallback_prefs.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/platform/app_platform_capabilities.dart';
import '../../core/platform/app_platform_capability_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../core/sync/vault_reset_error.dart';
import '../../core/desktop/desktop_boot_prefs.dart';
import '../../core/desktop/desktop_quick_capture_hotkey_prefs.dart';
import '../../core/desktop/system_hotkey_conflicts.dart';
import '../../core/desktop/system_hotkey_recorder.dart';
import '../../core/update/update_badge_prefs.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../src/rust/api/oplog_maintenance.dart' as rust_oplog_maintenance;
import '../../i18n/locale_prefs.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../web_app/web_formal_settings_scope.dart';
import '../actions/settings/actions_settings_store.dart';
import 'cloud_runtime_mode_page.dart';
import 'ai_settings_page.dart';
import 'sync_settings_page.dart';
import 'external_import_page.dart';
import 'migration_archive_page.dart';
import 'diagnostics_page.dart';
import 'about_page.dart';
import 'oplog_maintenance_scope.dart';
import '../welcome/welcome_page.dart';

part 'settings_page_build.dart';
part 'settings_page_reset_actions.dart';
part 'settings_page_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

@visibleForTesting
bool debugShowsAppearancePreferences(
  AppPlatformCapabilities capabilities, {
  bool isWeb = kIsWeb,
}) {
  return !(isWeb || capabilities.usesCloudSessionModel);
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _appLockEnabled;
  bool? _biometricUnlockEnabled;
  AppLocale? _localeOverride;
  ActionsSettings? _actionsSettings;
  bool? _reviewReminderInAppFallbackEnabled;
  DesktopBootConfig _desktopBootConfig = DesktopBootConfig.defaults;
  bool _busy = false;

  SubscriptionStatusController? _subscriptionController;
  SubscriptionStatus _lastSubscriptionStatus = SubscriptionStatus.unknown;
  CloudAuthController? _cloudAuthController;
  Listenable? _cloudAuthListenable;
  String? _lastCloudUid;

  void _setState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    } else {
      fn();
    }
  }

  static const _kAppLockEnabledPrefsKey = 'app_lock_enabled_v1';
  static const _kBiometricUnlockEnabledPrefsKey = 'biometric_unlock_enabled_v1';
  static const _kMasterPasswordSetupRequiredPrefsKey =
      'master_password_setup_required_v1';

  HotKey _defaultQuickCaptureHotKey(TargetPlatform platform) => HotKey(
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

  String _formatHotKey(HotKey hotKey) {
    final platform = defaultTargetPlatform;
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
    return platform == TargetPlatform.macOS
        ? pieces.join()
        : pieces.join(' + ');
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

  String? _quickCaptureHotkeyError(BuildContext context, HotKey hotKey) {
    final t = context.t.settings.quickCaptureHotkey;

    final modifiers = hotKey.modifiers ?? [];
    if (modifiers.isEmpty) return t.validation.missingModifier;

    final isModifierKey = HotKeyModifier.values.any(
      (m) => m.physicalKeys.contains(hotKey.physicalKey),
    );
    if (isModifierKey) return t.validation.modifierOnly;

    final conflict = systemHotkeyConflict(
      hotKey: hotKey,
      platform: defaultTargetPlatform,
    );
    if (conflict != null) {
      return t.validation.systemConflict(
        name: _systemHotkeyConflictName(context, conflict),
      );
    }

    return null;
  }

  bool _defaultSystemUnlockEnabled() {
    if (!AppPlatformCapabilityScope.of(context).supportsBiometricUnlock) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows;
  }

  bool _isDesktopPlatform() {
    return AppPlatformCapabilityScope.of(context).supportsDesktopBootSettings;
  }

  String _normalizeAppLockWording(String text) {
    return text
        .replaceAll('master password', 'app lock password')
        .replaceAll('Master password', 'App lock password')
        .replaceAll('主密码', '应用锁密码');
  }

  rust_oplog_maintenance.OplogMaintenanceBackend _maintenanceBackendFor(
    SyncBackendType backendType,
  ) {
    return switch (backendType) {
      SyncBackendType.webdav =>
        rust_oplog_maintenance.OplogMaintenanceBackend.webDav,
      SyncBackendType.localDir =>
        rust_oplog_maintenance.OplogMaintenanceBackend.localDir,
      SyncBackendType.managedVault =>
        rust_oplog_maintenance.OplogMaintenanceBackend.managedVault,
    };
  }

  Future<void> _runOplogMaintenanceDebug() async {
    if (_busy) return;

    final messenger = ScaffoldMessenger.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final store = _syncConfigStore(context);

    setState(() => _busy = true);
    try {
      final sync = await store.loadConfiguredSync();
      if (sync == null) {
        throw StateError('sync_not_configured');
      }

      final scopeId = computeOplogMaintenanceScopeId(
        OplogMaintenanceScopeInput.fromSyncConfig(sync),
      );
      final appDir = (await getApplicationSupportDirectory()).path;
      final stats = await rust_oplog_maintenance.dbRunOplogMaintenance(
        appDir: appDir,
        key: sessionKey,
        backend: _maintenanceBackendFor(sync.backendType),
        scopeId: scopeId,
      );

      if (!mounted) return;
      final before = stats.beforeCount.toString();
      final after = stats.afterCount.toString();
      final pruned = stats.prunedCount.toString();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.t.settings.debugOplogMaintenance.completed(
              pruned: pruned,
              before: before,
              after: after,
            ),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.t.settings.debugOplogMaintenance.failed(error: '$e'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _subscriptionController?.removeListener(_onSubscriptionChanged);
    _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kAppLockEnabledPrefsKey) ?? false;
    final biometricEnabled = prefs.getBool(_kBiometricUnlockEnabledPrefsKey) ??
        _defaultSystemUnlockEnabled();
    await ReviewReminderInAppFallbackPrefs.load();
    final reviewReminderInAppFallbackEnabled =
        ReviewReminderInAppFallbackPrefs.value.value;
    final rawLocaleOverride = prefs.getString(kAppLocaleOverridePrefsKey);
    AppLocale? localeOverride;
    if (rawLocaleOverride != null && rawLocaleOverride.trim().isNotEmpty) {
      try {
        localeOverride = AppLocaleUtils.parse(rawLocaleOverride);
      } catch (_) {
        localeOverride = null;
      }
    }
    if (!mounted) return;
    final actionsSettings = await ActionsSettingsStore.load();
    if (!mounted) return;

    var desktopBootConfig = _desktopBootConfig;
    if (_isDesktopPlatform()) {
      await DesktopBootPrefs.load();
      desktopBootConfig = DesktopBootPrefs.value.value;
    }

    if (!mounted) return;
    setState(() {
      _appLockEnabled = enabled;
      _biometricUnlockEnabled = biometricEnabled;
      _reviewReminderInAppFallbackEnabled = reviewReminderInAppFallbackEnabled;
      _localeOverride = localeOverride;
      _actionsSettings = actionsSettings;
      _desktopBootConfig = desktopBootConfig;
    });
  }

  void _onSubscriptionChanged() {
    final controller = _subscriptionController;
    if (controller == null) return;

    final next = controller.status;
    if (next == _lastSubscriptionStatus) return;
    _lastSubscriptionStatus = next;
    unawaited(_maybeDisableCloudEmbeddingsIfNotAllowed());
  }

  void _onCloudAuthChanged() {
    final controller = _cloudAuthController;
    if (controller == null) return;

    final uid = controller.uid;
    if (uid == _lastCloudUid) return;

    _lastCloudUid = uid;
    unawaited(_maybeDisableCloudEmbeddingsIfNotAllowed());
  }

  Future<void> _maybeDisableCloudEmbeddingsIfNotAllowed() async {
    return;
  }

  String _localeLabel(BuildContext context, AppLocale locale) {
    return switch (locale) {
      AppLocale.en => context.t.settings.language.options.en,
      AppLocale.zhCn => context.t.settings.language.options.zhCn,
    };
  }

  String _currentLanguageLabel(BuildContext context) {
    final override = _localeOverride;
    if (override == null) {
      final deviceLocale = AppLocaleUtils.findDeviceLocale();
      return context.t.settings.language.options.systemWithValue(
        value: _localeLabel(context, deviceLocale),
      );
    }
    return _localeLabel(context, override);
  }

  Future<void> _selectLanguage() async {
    if (_busy) return;

    final selected = await showDialog<AppLocale?>(
      context: context,
      builder: (context) {
        final t = context.t;
        final current = _localeOverride;
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

    if (!mounted || selected == _localeOverride) return;
    setState(() => _localeOverride = selected);
    await setLocaleOverride(selected);
  }

  Future<void> _setAppLock(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);
      final sessionScope = SessionScope.of(context);
      final sessionKey = sessionScope.sessionKey;
      final lock = sessionScope.lock;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAppLockEnabledPrefsKey, enabled);
      if (!enabled) {
        await prefs.remove(_kMasterPasswordSetupRequiredPrefsKey);
      }

      final isMasterPasswordSet = await backend.isMasterPasswordSet();
      if (enabled && !isMasterPasswordSet) {
        await prefs.setBool(_kMasterPasswordSetupRequiredPrefsKey, true);
        await BackgroundSync.refreshSchedule(backend: backend);
        if (mounted) {
          setState(() => _appLockEnabled = true);
        }
        lock();
        return;
      }

      final biometricEnabled =
          _biometricUnlockEnabled ?? _defaultSystemUnlockEnabled();
      final isMacNoKeychain =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
      final shouldPersist = !isMacNoKeychain && (!enabled || biometricEnabled);
      if (shouldPersist) {
        await backend.saveSessionKey(sessionKey);
      } else {
        await backend.clearSavedSessionKey();
      }
      await prefs.remove(_kMasterPasswordSetupRequiredPrefsKey);
      await BackgroundSync.refreshSchedule(backend: backend);
      if (mounted) setState(() => _appLockEnabled = enabled);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lockNow() async {
    if (_busy) return;

    final backend = AppBackendScope.of(context);
    final prefs = await SharedPreferences.getInstance();
    final isMasterPasswordSet = await backend.isMasterPasswordSet();
    if (!isMasterPasswordSet) {
      await prefs.setBool(_kMasterPasswordSetupRequiredPrefsKey, true);
    }

    if (!mounted) return;
    SessionScope.of(context).lock();
  }

  Future<void> _setBiometricUnlock(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBiometricUnlockEnabledPrefsKey, enabled);

      if (enabled) {
        await backend.saveSessionKey(sessionKey);
      } else {
        await backend.clearSavedSessionKey();
      }

      await BackgroundSync.refreshSchedule(backend: backend);
      if (mounted) setState(() => _biometricUnlockEnabled = enabled);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setReviewReminderInAppFallback(bool enabled) async {
    if (_busy) return;

    final previous = _reviewReminderInAppFallbackEnabled ??
        ReviewReminderInAppFallbackPrefs.defaultValue;
    setState(() => _reviewReminderInAppFallbackEnabled = enabled);

    try {
      await ReviewReminderInAppFallbackPrefs.setEnabled(enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _reviewReminderInAppFallbackEnabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _setDesktopStartWithSystem(bool enabled) async {
    if (_busy || !_isDesktopPlatform()) return;

    final previous = _desktopBootConfig;
    setState(() {
      _desktopBootConfig =
          _desktopBootConfig.copyWith(startWithSystem: enabled);
    });

    try {
      await DesktopBootPrefs.setStartWithSystem(enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _desktopBootConfig = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _setDesktopSilentStartup(bool enabled) async {
    if (_busy || !_isDesktopPlatform()) return;

    final previous = _desktopBootConfig;
    setState(() {
      _desktopBootConfig = _desktopBootConfig.copyWith(silentStartup: enabled);
    });

    try {
      await DesktopBootPrefs.setSilentStartup(enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _desktopBootConfig = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _setDesktopKeepRunningInBackground(bool enabled) async {
    if (_busy || !_isDesktopPlatform()) return;

    final previous = _desktopBootConfig;
    setState(() {
      _desktopBootConfig =
          _desktopBootConfig.copyWith(keepRunningInBackground: enabled);
    });

    try {
      await DesktopBootPrefs.setKeepRunningInBackground(enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _desktopBootConfig = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _pickActionsTime({
    required TimeOfDay initial,
    required Future<void> Function(TimeOfDay value) persist,
  }) async {
    if (_busy) return;

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await persist(picked);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final subscriptionController = SubscriptionScope.maybeOf(context);
    if (!identical(subscriptionController, _subscriptionController)) {
      _subscriptionController?.removeListener(_onSubscriptionChanged);
      _subscriptionController = subscriptionController;
      _lastSubscriptionStatus =
          subscriptionController?.status ?? SubscriptionStatus.unknown;
      _subscriptionController?.addListener(_onSubscriptionChanged);
    }

    final cloudAuthController = CloudAuthScope.maybeOf(context)?.controller;
    if (!identical(cloudAuthController, _cloudAuthController)) {
      _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
      _cloudAuthController = cloudAuthController;
      final listenable = cloudAuthController is Listenable
          ? cloudAuthController as Listenable
          : null;
      _cloudAuthListenable = listenable;
      listenable?.addListener(_onCloudAuthChanged);
      _lastCloudUid = cloudAuthController?.uid;
    }

    _appLockEnabled ??= false;
    _biometricUnlockEnabled ??= _defaultSystemUnlockEnabled();
    _load();
    unawaited(_maybeDisableCloudEmbeddingsIfNotAllowed());

    if (AppPlatformCapabilityScope.of(context).supportsDesktopHotkey) {
      unawaited(DesktopQuickCaptureHotkeyPrefs.load());
    }
  }

  Future<void> _editQuickCaptureHotkey() async {
    if (_busy) return;

    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;

    await DesktopQuickCaptureHotkeyPrefs.load();
    if (!mounted) return;

    final defaultHotKey = _defaultQuickCaptureHotKey(defaultTargetPlatform);
    final existing =
        DesktopQuickCaptureHotkeyPrefs.value.value ?? defaultHotKey;

    HotKey draft = existing;
    String? error = _quickCaptureHotkeyError(context, draft);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void onRecorded(HotKey hotKey) {
              setDialogState(() {
                draft = hotKey;
                error = _quickCaptureHotkeyError(dialogContext, draft);
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
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatHotKey(draft),
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .titleMedium,
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
                  child:
                      Text(t.settings.quickCaptureHotkey.actions.resetDefault),
                ),
                FilledButton(
                  onPressed: error == null
                      ? () async {
                          await DesktopQuickCaptureHotkeyPrefs.setHotKey(draft);
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content:
                                  Text(t.settings.quickCaptureHotkey.saved),
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

  @override
  Widget build(BuildContext context) => _buildSettingsPage(context);
}
