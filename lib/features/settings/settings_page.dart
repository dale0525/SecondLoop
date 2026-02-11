import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme_mode_prefs.dart';
import '../../core/ai/ai_routing.dart';
import '../../core/ai/embeddings_data_consent_prefs.dart';
import '../../core/ai/semantic_parse_data_consent_prefs.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_controller.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../core/desktop/desktop_quick_capture_hotkey_prefs.dart';
import '../../core/desktop/system_hotkey_conflicts.dart';
import '../../core/desktop/system_hotkey_recorder.dart';
import '../../i18n/locale_prefs.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../actions/settings/actions_settings_store.dart';
import 'cloud_account_page.dart';
import 'embedding_profiles_page.dart';
import 'ai_settings_page.dart';
import 'llm_profiles_page.dart';
import 'media_annotation_settings_page.dart';
import 'sync_settings_page.dart';
import 'semantic_search_debug_page.dart';
import 'diagnostics_page.dart';

part 'settings_page_build.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _appLockEnabled;
  bool? _biometricUnlockEnabled;
  bool? _cloudEmbeddingsEnabled;
  bool _cloudEmbeddingsConfigured = false;
  bool? _semanticParseEnabled;
  bool _semanticParseConfigured = false;
  bool? _byokConfigured;
  AppLocale? _localeOverride;
  ActionsSettings? _actionsSettings;
  bool _busy = false;

  SubscriptionStatusController? _subscriptionController;
  SubscriptionStatus _lastSubscriptionStatus = SubscriptionStatus.unknown;
  CloudAuthController? _cloudAuthController;
  Listenable? _cloudAuthListenable;
  String? _lastCloudUid;
  VoidCallback? _cloudEmbeddingsPrefsListener;
  VoidCallback? _semanticParsePrefsListener;

  static const _kAppLockEnabledPrefsKey = 'app_lock_enabled_v1';
  static const _kBiometricUnlockEnabledPrefsKey = 'biometric_unlock_enabled_v1';

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
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  String _joinRemotePath(String root, String child) {
    final r = root.trim().replaceAll(RegExp(r'/+$'), '');
    final c = child.trim().replaceAll(RegExp(r'^/+'), '');
    if (r.isEmpty) return c;
    if (c.isEmpty) return r;
    return '$r/$c';
  }

  Future<void> _resetLocalData({required bool clearAllRemoteData}) async {
    if (_busy) return;

    final t = context.t;
    final dialogTitle = clearAllRemoteData
        ? t.settings.resetLocalDataAllDevices.dialogTitle
        : t.settings.resetLocalDataThisDeviceOnly.dialogTitle;
    final dialogBody = clearAllRemoteData
        ? t.settings.resetLocalDataAllDevices.dialogBody
        : t.settings.resetLocalDataThisDeviceOnly.dialogBody;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: Text(dialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t.common.actions.reset),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final backend = AppBackendScope.of(context);
    final lock = SessionScope.of(context).lock;
    final messenger = ScaffoldMessenger.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    SyncEngineScope.maybeOf(context)?.stop();

    setState(() => _busy = true);
    try {
      final store = SyncConfigStore();
      final sync = await store.loadConfiguredSync();
      if (sync != null) {
        final deviceId =
            clearAllRemoteData ? null : await backend.getOrCreateDeviceId();
        await switch (sync.backendType) {
          SyncBackendType.webdav => backend.syncWebdavClearRemoteRoot(
              baseUrl: sync.baseUrl ?? '',
              username: sync.username,
              password: sync.password,
              remoteRoot: deviceId == null
                  ? sync.remoteRoot
                  : _joinRemotePath(sync.remoteRoot, deviceId),
            ),
          SyncBackendType.localDir => backend.syncLocaldirClearRemoteRoot(
              localDir: sync.localDir ?? '',
              remoteRoot: deviceId == null
                  ? sync.remoteRoot
                  : _joinRemotePath(sync.remoteRoot, deviceId),
            ),
          SyncBackendType.managedVault => () async {
              final idToken = await CloudAuthScope.maybeOf(context)
                  ?.controller
                  .getIdToken();
              if (idToken == null || idToken.trim().isEmpty) {
                throw StateError('missing_cloud_id_token');
              }
              final baseUrl = sync.baseUrl ?? '';
              if (baseUrl.trim().isEmpty) throw StateError('missing_base_url');

              if (deviceId == null) {
                await backend.syncManagedVaultClearVault(
                  baseUrl: baseUrl,
                  vaultId: sync.remoteRoot,
                  idToken: idToken,
                );
                return;
              }

              await backend.syncManagedVaultClearDevice(
                baseUrl: baseUrl,
                vaultId: sync.remoteRoot,
                idToken: idToken,
                deviceId: deviceId,
              );
            }(),
        };
      }

      await backend.resetVaultDataPreservingLlmProfiles(sessionKey);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAppLockEnabledPrefsKey);
      await prefs.remove(_kBiometricUnlockEnabledPrefsKey);
      await backend.clearSavedSessionKey();

      await BackgroundSync.refreshSchedule(backend: backend);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(clearAllRemoteData
              ? t.settings.resetLocalDataAllDevices.failed(error: '$e')
              : t.settings.resetLocalDataThisDeviceOnly.failed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    lock();
  }

  @override
  void initState() {
    super.initState();

    void onCloudEmbeddingsPrefChanged() {
      if (!mounted) return;
      final next = EmbeddingsDataConsentPrefs.value.value;
      setState(() {
        _cloudEmbeddingsConfigured = next != null;
        _cloudEmbeddingsEnabled = next ?? false;
      });
    }

    _cloudEmbeddingsPrefsListener = onCloudEmbeddingsPrefChanged;
    EmbeddingsDataConsentPrefs.value.addListener(onCloudEmbeddingsPrefChanged);

    void onSemanticParsePrefChanged() {
      if (!mounted) return;
      final next = SemanticParseDataConsentPrefs.value.value;
      setState(() {
        _semanticParseConfigured = next != null;
        _semanticParseEnabled = next ?? false;
      });
    }

    _semanticParsePrefsListener = onSemanticParsePrefChanged;
    SemanticParseDataConsentPrefs.value.addListener(onSemanticParsePrefChanged);
  }

  @override
  void dispose() {
    _subscriptionController?.removeListener(_onSubscriptionChanged);
    _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
    final listener = _cloudEmbeddingsPrefsListener;
    if (listener != null) {
      EmbeddingsDataConsentPrefs.value.removeListener(listener);
    }
    final semanticParseListener = _semanticParsePrefsListener;
    if (semanticParseListener != null) {
      SemanticParseDataConsentPrefs.value.removeListener(semanticParseListener);
    }
    super.dispose();
  }

  Future<void> _load() async {
    final backend =
        context.dependOnInheritedWidgetOfExactType<AppBackendScope>()?.backend;
    final sessionKey = SessionScope.of(context).sessionKey;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kAppLockEnabledPrefsKey) ?? false;
    final biometricEnabled = prefs.getBool(_kBiometricUnlockEnabledPrefsKey) ??
        _defaultSystemUnlockEnabled();
    final cloudEmbeddingsConfigured =
        prefs.containsKey(EmbeddingsDataConsentPrefs.prefsKey);
    final cloudEmbeddingsEnabled = cloudEmbeddingsConfigured
        ? (prefs.getBool(EmbeddingsDataConsentPrefs.prefsKey) ?? false)
        : false;
    final semanticParseConfigured =
        prefs.containsKey(SemanticParseDataConsentPrefs.prefsKey);
    final semanticParseEnabled = semanticParseConfigured
        ? (prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false)
        : false;

    bool? byokConfigured;
    if (backend == null) {
      byokConfigured = null;
    } else {
      try {
        byokConfigured = await hasActiveLlmProfile(backend, sessionKey);
      } catch (_) {
        byokConfigured = null;
      }
    }

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
    setState(() {
      _appLockEnabled = enabled;
      _biometricUnlockEnabled = biometricEnabled;
      _cloudEmbeddingsEnabled = cloudEmbeddingsEnabled;
      _cloudEmbeddingsConfigured = cloudEmbeddingsConfigured;
      _semanticParseEnabled = semanticParseEnabled;
      _semanticParseConfigured = semanticParseConfigured;
      _byokConfigured = byokConfigured;
      _localeOverride = localeOverride;
      _actionsSettings = actionsSettings;
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
    final subscriptionStatus =
        _subscriptionController?.status ?? SubscriptionStatus.unknown;
    final cloudUid = (_cloudAuthController?.uid ?? '').trim();

    if (subscriptionStatus == SubscriptionStatus.unknown) return;

    final allowed = subscriptionStatus == SubscriptionStatus.entitled &&
        cloudUid.isNotEmpty;
    if (allowed) return;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(EmbeddingsDataConsentPrefs.prefsKey);
    if (enabled != true) return;

    await EmbeddingsDataConsentPrefs.setEnabled(prefs, false);
    if (!mounted) return;
    await _load();
  }

  Future<void> _setCloudEmbeddingsEnabled(bool enabled) async {
    if (_busy) return;

    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final t = context.t;
          return AlertDialog(
            title: Text(t.settings.cloudEmbeddings.dialogTitle),
            content: Text(t.settings.cloudEmbeddings.dialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.common.actions.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.settings.cloudEmbeddings.dialogActions.enable),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await EmbeddingsDataConsentPrefs.setEnabled(prefs, enabled);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setSemanticParseEnabled(bool enabled) async {
    if (_busy) return;

    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final t = context.t;
          return AlertDialog(
            title: Text(t.settings.semanticParseAutoActions.dialogTitle),
            content: Text(t.settings.semanticParseAutoActions.dialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.common.actions.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  t.settings.semanticParseAutoActions.dialogActions.enable,
                ),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await SemanticParseDataConsentPrefs.setEnabled(prefs, enabled);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  String _themeModeLabel(BuildContext context, ThemeMode mode) {
    final t = context.t;
    return switch (mode) {
      ThemeMode.system => t.settings.theme.options.system,
      ThemeMode.light => t.settings.theme.options.light,
      ThemeMode.dark => t.settings.theme.options.dark,
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
      final sessionKey = SessionScope.of(context).sessionKey;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAppLockEnabledPrefsKey, enabled);
      final biometricEnabled =
          _biometricUnlockEnabled ?? _defaultSystemUnlockEnabled();
      final shouldPersist = !enabled || biometricEnabled;
      if (shouldPersist) {
        await backend.saveSessionKey(sessionKey);
      } else {
        await backend.clearSavedSessionKey();
      }
      await BackgroundSync.refreshSchedule(backend: backend);
      if (mounted) setState(() => _appLockEnabled = enabled);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux)) {
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
