import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/background_sync.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/locale_prefs.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../actions/settings/actions_settings_store.dart';
import 'cloud_account_page.dart';
import 'llm_profiles_page.dart';
import 'sync_settings_page.dart';
import 'semantic_search_debug_page.dart';
import 'diagnostics_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _appLockEnabled;
  bool? _biometricUnlockEnabled;
  AppLocale? _localeOverride;
  ActionsSettings? _actionsSettings;
  bool _busy = false;

  static const _kAppLockEnabledPrefsKey = 'app_lock_enabled_v1';
  static const _kBiometricUnlockEnabledPrefsKey = 'biometric_unlock_enabled_v1';

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
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    lock();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kAppLockEnabledPrefsKey) ?? false;
    final biometricEnabled = prefs.getBool(_kBiometricUnlockEnabledPrefsKey) ??
        _defaultSystemUnlockEnabled();
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
      _localeOverride = localeOverride;
      _actionsSettings = actionsSettings;
    });
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
    _appLockEnabled ??= false;
    _biometricUnlockEnabled ??= _defaultSystemUnlockEnabled();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _appLockEnabled;
    final biometricEnabled = _biometricUnlockEnabled;
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);

    Widget sectionCard(List<Widget> children) {
      return SlSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i != 0) const Divider(height: 1),
              children[i],
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.t.settings.sections.general,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        sectionCard([
          ListTile(
            title: Text(context.t.settings.language.title),
            subtitle: Text(context.t.settings.language.subtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_currentLanguageLabel(context)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: _busy ? null : _selectLanguage,
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          context.t.settings.sections.security,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        sectionCard([
          SwitchListTile(
            title: Text(context.t.settings.autoLock.title),
            subtitle: Text(context.t.settings.autoLock.subtitle),
            value: enabled ?? false,
            onChanged: (_busy || enabled == null) ? null : _setAppLock,
          ),
          if ((enabled ?? false) && (isMobile || isDesktop))
            SwitchListTile(
              title: Text(
                isMobile
                    ? context.t.settings.systemUnlock.titleMobile
                    : context.t.settings.systemUnlock.titleDesktop,
              ),
              subtitle: Text(
                isMobile
                    ? context.t.settings.systemUnlock.subtitleMobile
                    : context.t.settings.systemUnlock.subtitleDesktop,
              ),
              value: biometricEnabled ?? false,
              onChanged: (_busy || biometricEnabled == null)
                  ? null
                  : _setBiometricUnlock,
            ),
          ListTile(
            title: Text(context.t.settings.lockNow.title),
            subtitle: Text(context.t.settings.lockNow.subtitle),
            onTap: _busy ? null : SessionScope.of(context).lock,
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          context.t.settings.sections.connections,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        sectionCard([
          ListTile(
            title: Text(context.t.settings.cloudAccount.title),
            subtitle: Text(context.t.settings.cloudAccount.subtitle),
            onTap: _busy
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CloudAccountPage(),
                      ),
                    );
                  },
          ),
          ListTile(
            title: Text(context.t.settings.llmProfiles.title),
            subtitle: Text(context.t.settings.llmProfiles.subtitle),
            onTap: _busy
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LlmProfilesPage(),
                      ),
                    );
                  },
          ),
          ListTile(
            title: Text(context.t.settings.sync.title),
            subtitle: Text(context.t.settings.sync.subtitle),
            onTap: _busy
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SyncSettingsPage(),
                      ),
                    );
                  },
          ),
          ListTile(
            key: const ValueKey('settings_diagnostics'),
            title: Text(context.t.settings.diagnostics.title),
            subtitle: Text(context.t.settings.diagnostics.subtitle),
            onTap: _busy
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiagnosticsPage(),
                      ),
                    );
                  },
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          context.t.settings.sections.actions,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        sectionCard([
          ListTile(
            title: Text(context.t.settings.actionsReview.morningTime.title),
            subtitle:
                Text(context.t.settings.actionsReview.morningTime.subtitle),
            trailing:
                Text(_actionsSettings?.morningTime.format(context) ?? '—'),
            onTap: (_busy || _actionsSettings == null)
                ? null
                : () => _pickActionsTime(
                      initial: _actionsSettings!.morningTime,
                      persist: ActionsSettingsStore.setMorningTime,
                    ),
          ),
          ListTile(
            title: Text(context.t.settings.actionsReview.dayEndTime.title),
            subtitle:
                Text(context.t.settings.actionsReview.dayEndTime.subtitle),
            trailing: Text(_actionsSettings?.dayEndTime.format(context) ?? '—'),
            onTap: (_busy || _actionsSettings == null)
                ? null
                : () => _pickActionsTime(
                      initial: _actionsSettings!.dayEndTime,
                      persist: ActionsSettingsStore.setDayEndTime,
                    ),
          ),
          ListTile(
            title: Text(context.t.settings.actionsReview.weeklyTime.title),
            subtitle:
                Text(context.t.settings.actionsReview.weeklyTime.subtitle),
            trailing:
                Text(_actionsSettings?.weeklyReviewTime.format(context) ?? '—'),
            onTap: (_busy || _actionsSettings == null)
                ? null
                : () => _pickActionsTime(
                      initial: _actionsSettings!.weeklyReviewTime,
                      persist: ActionsSettingsStore.setWeeklyReviewTime,
                    ),
          ),
        ]),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          Text(
            context.t.settings.sections.debug,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          sectionCard([
            ListTile(
              title: Text(
                  context.t.settings.debugResetLocalDataThisDeviceOnly.title),
              subtitle: Text(context
                  .t.settings.debugResetLocalDataThisDeviceOnly.subtitle),
              onTap: _busy
                  ? null
                  : () => _resetLocalData(clearAllRemoteData: false),
            ),
            ListTile(
              title:
                  Text(context.t.settings.debugResetLocalDataAllDevices.title),
              subtitle: Text(
                  context.t.settings.debugResetLocalDataAllDevices.subtitle),
              onTap: _busy
                  ? null
                  : () => _resetLocalData(clearAllRemoteData: true),
            ),
            ListTile(
              title: Text(context.t.settings.debugSemanticSearch.title),
              subtitle: Text(context.t.settings.debugSemanticSearch.subtitle),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SemanticSearchDebugPage(),
                  ),
                );
              },
            ),
          ]),
        ],
      ],
    );
  }
}
