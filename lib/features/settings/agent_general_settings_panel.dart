import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/desktop/desktop_boot_prefs.dart';
import '../../core/desktop/desktop_quick_capture_hotkey_prefs.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/notifications/review_reminder_in_app_fallback_prefs.dart';
import '../../core/platform/app_platform_capabilities.dart';
import '../../core/platform/app_platform_capability_scope.dart';
import '../../core/update/update_badge_prefs.dart';
import '../../i18n/locale_prefs.dart';
import '../../i18n/strings.g.dart';
import '../actions/settings/actions_settings_store.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../welcome/welcome_page.dart';
import 'about_page.dart';
import 'diagnostics_page.dart';
import 'settings_general_helpers.dart';
import 'settings_theme_mode_row.dart';
import 'settings_ui.dart';

final class AgentGeneralSettingsPanel extends StatefulWidget {
  const AgentGeneralSettingsPanel({super.key});

  @override
  State<AgentGeneralSettingsPanel> createState() =>
      _AgentGeneralSettingsPanelState();
}

final class _AgentGeneralSettingsPanelState
    extends State<AgentGeneralSettingsPanel> {
  AppLocale? _localeOverride;
  ActionsSettings? _actionsSettings;
  bool? _reviewReminderInAppFallbackEnabled;
  DesktopBootConfig _desktopBootConfig = DesktopBootConfig.defaults;
  AppPlatformCapabilities? _capabilities;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final capabilities = AppPlatformCapabilityScope.of(context);
    if (capabilities == _capabilities) return;

    _capabilities = capabilities;
    unawaited(_load(capabilities));
  }

  Future<void> _load(AppPlatformCapabilities capabilities) async {
    await ReviewReminderInAppFallbackPrefs.load();
    final reviewReminderInAppFallbackEnabled =
        ReviewReminderInAppFallbackPrefs.value.value;
    final localeOverride = await readLocaleOverride();
    final actionsSettings = await ActionsSettingsStore.load();

    var desktopBootConfig = DesktopBootConfig.defaults;
    if (capabilities.supportsDesktopBootSettings) {
      await DesktopBootPrefs.load();
      desktopBootConfig = DesktopBootPrefs.value.value;
    }
    if (capabilities.supportsDesktopHotkey) {
      await DesktopQuickCaptureHotkeyPrefs.load();
    }

    if (!mounted || capabilities != _capabilities) return;
    setState(() {
      _reviewReminderInAppFallbackEnabled = reviewReminderInAppFallbackEnabled;
      _localeOverride = localeOverride;
      _actionsSettings = actionsSettings;
      _desktopBootConfig = desktopBootConfig;
    });
  }

  Future<void> _selectLanguage() async {
    if (_busy) return;

    final selected =
        await selectSettingsLanguageOverride(context, _localeOverride);
    if (!mounted || selected == _localeOverride) return;

    setState(() => _localeOverride = selected);
    await setLocaleOverride(selected);
  }

  Future<void> _setReviewReminderInAppFallback(bool enabled) async {
    if (_busy) return;

    final previous = _reviewReminderInAppFallbackEnabled ??
        ReviewReminderInAppFallbackPrefs.defaultValue;
    setState(() => _reviewReminderInAppFallbackEnabled = enabled);

    try {
      await ReviewReminderInAppFallbackPrefs.setEnabled(enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _reviewReminderInAppFallbackEnabled = previous);
      _showSaveFailed(error);
    }
  }

  Future<void> _setDesktopStartWithSystem(bool enabled) async {
    if (_busy || !(_capabilities?.supportsDesktopBootSettings ?? false)) {
      return;
    }

    final previous = _desktopBootConfig;
    setState(() {
      _desktopBootConfig =
          _desktopBootConfig.copyWith(startWithSystem: enabled);
    });

    try {
      await DesktopBootPrefs.setStartWithSystem(enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _desktopBootConfig = previous);
      _showSaveFailed(error);
    }
  }

  Future<void> _setDesktopSilentStartup(bool enabled) async {
    if (_busy || !(_capabilities?.supportsDesktopBootSettings ?? false)) {
      return;
    }

    final previous = _desktopBootConfig;
    setState(() {
      _desktopBootConfig = _desktopBootConfig.copyWith(silentStartup: enabled);
    });

    try {
      await DesktopBootPrefs.setSilentStartup(enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _desktopBootConfig = previous);
      _showSaveFailed(error);
    }
  }

  Future<void> _setDesktopKeepRunningInBackground(bool enabled) async {
    if (_busy || !(_capabilities?.supportsDesktopBootSettings ?? false)) {
      return;
    }

    final previous = _desktopBootConfig;
    setState(() {
      _desktopBootConfig =
          _desktopBootConfig.copyWith(keepRunningInBackground: enabled);
    });

    try {
      await DesktopBootPrefs.setKeepRunningInBackground(enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _desktopBootConfig = previous);
      _showSaveFailed(error);
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
      final capabilities = _capabilities;
      if (capabilities != null) {
        await _load(capabilities);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editQuickCaptureHotkey() async {
    if (_busy) return;
    await editSettingsQuickCaptureHotkey(context);
  }

  void _showSaveFailed(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.errors.saveFailed(error: '$error')),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final agentGeneral = t.settings.agentUi.general;
    final capabilities =
        _capabilities ?? AppPlatformCapabilityScope.of(context);
    final showsThemeMode = !kIsWeb && !capabilities.usesCloudSessionModel;
    final showsDesktopSection = capabilities.supportsDesktopBootSettings ||
        capabilities.supportsDesktopHotkey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          agentGeneral.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapXs),
        Text(
          agentGeneral.subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapLg),
        SettingsSection(
          title: agentGeneral.sections.appearance,
          children: [
            if (showsThemeMode) SettingsThemeModeRow(enabled: !_busy),
            SettingsRow(
              key: const ValueKey('settings_language'),
              title: t.settings.language.title,
              body: t.settings.language.subtitle,
              trailing: Text(
                currentSettingsLanguageLabel(context, _localeOverride),
              ),
              showChevron: true,
              enabled: !_busy,
              onTap: _selectLanguage,
            ),
          ],
        ),
        const SizedBox(height: AgentDesignTokens.gapLg),
        SettingsSection(
          title: agentGeneral.sections.reminders,
          children: [
            SettingsSwitchRow(
              key: const ValueKey(
                'settings_review_reminder_in_app_fallback_switch',
              ),
              title: t.settings.actionsReview.inAppFallback.title,
              body: t.settings.actionsReview.inAppFallback.subtitle,
              value: _reviewReminderInAppFallbackEnabled ??
                  ReviewReminderInAppFallbackPrefs.defaultValue,
              onChanged: (_busy || _reviewReminderInAppFallbackEnabled == null)
                  ? null
                  : _setReviewReminderInAppFallback,
            ),
            SettingsRow(
              key: const ValueKey('settings_actions_review_morning_time'),
              title: t.settings.actionsReview.morningTime.title,
              body: t.settings.actionsReview.morningTime.subtitle,
              trailing: Text(
                _actionsSettings?.morningTime.format(context) ?? '...',
              ),
              showChevron: true,
              enabled: !_busy && _actionsSettings != null,
              onTap: () {
                final settings = _actionsSettings;
                if (settings == null) return;
                unawaited(
                  _pickActionsTime(
                    initial: settings.morningTime,
                    persist: ActionsSettingsStore.setMorningTime,
                  ),
                );
              },
            ),
            SettingsRow(
              key: const ValueKey('settings_actions_review_day_end_time'),
              title: t.settings.actionsReview.dayEndTime.title,
              body: t.settings.actionsReview.dayEndTime.subtitle,
              trailing: Text(
                _actionsSettings?.dayEndTime.format(context) ?? '...',
              ),
              showChevron: true,
              enabled: !_busy && _actionsSettings != null,
              onTap: () {
                final settings = _actionsSettings;
                if (settings == null) return;
                unawaited(
                  _pickActionsTime(
                    initial: settings.dayEndTime,
                    persist: ActionsSettingsStore.setDayEndTime,
                  ),
                );
              },
            ),
            SettingsRow(
              key: const ValueKey('settings_actions_review_weekly_time'),
              title: t.settings.actionsReview.weeklyTime.title,
              body: t.settings.actionsReview.weeklyTime.subtitle,
              trailing: Text(
                _actionsSettings?.weeklyReviewTime.format(context) ?? '...',
              ),
              showChevron: true,
              enabled: !_busy && _actionsSettings != null,
              onTap: () {
                final settings = _actionsSettings;
                if (settings == null) return;
                unawaited(
                  _pickActionsTime(
                    initial: settings.weeklyReviewTime,
                    persist: ActionsSettingsStore.setWeeklyReviewTime,
                  ),
                );
              },
            ),
          ],
        ),
        if (showsDesktopSection) ...[
          const SizedBox(height: AgentDesignTokens.gapLg),
          SettingsSection(
            title: agentGeneral.sections.desktop,
            children: [
              if (capabilities.supportsDesktopBootSettings)
                SettingsSwitchRow(
                  key: const ValueKey('settings_start_with_system_switch'),
                  title: t.settings.desktopBoot.startWithSystem.title,
                  body: t.settings.desktopBoot.startWithSystem.subtitle,
                  value: _desktopBootConfig.startWithSystem,
                  onChanged: _busy ? null : _setDesktopStartWithSystem,
                ),
              if (capabilities.supportsDesktopBootSettings)
                SettingsSwitchRow(
                  key: const ValueKey('settings_silent_startup_switch'),
                  title: t.settings.desktopBoot.silentStartup.title,
                  body: t.settings.desktopBoot.silentStartup.subtitle,
                  value: _desktopBootConfig.silentStartup,
                  onChanged: _busy ? null : _setDesktopSilentStartup,
                ),
              if (capabilities.supportsDesktopBootSettings)
                SettingsSwitchRow(
                  key: const ValueKey(
                    'settings_keep_running_in_background_switch',
                  ),
                  title: t.settings.desktopBoot.keepRunningInBackground.title,
                  body: t.settings.desktopBoot.keepRunningInBackground.subtitle,
                  value: _desktopBootConfig.keepRunningInBackground,
                  onChanged: _busy ? null : _setDesktopKeepRunningInBackground,
                ),
              if (capabilities.supportsDesktopHotkey)
                SettingsRow(
                  key: const ValueKey('settings_quick_capture_hotkey'),
                  title: t.settings.quickCaptureHotkey.title,
                  body: t.settings.quickCaptureHotkey.subtitle,
                  trailing: ValueListenableBuilder(
                    valueListenable: DesktopQuickCaptureHotkeyPrefs.value,
                    builder: (context, override, child) {
                      final hotKey = override ??
                          defaultSettingsQuickCaptureHotKey(
                            defaultTargetPlatform,
                          );
                      return Text(
                        formatSettingsHotKey(hotKey, defaultTargetPlatform),
                      );
                    },
                  ),
                  showChevron: true,
                  enabled: !_busy,
                  onTap: _editQuickCaptureHotkey,
                ),
            ],
          ),
        ],
        const SizedBox(height: AgentDesignTokens.gapLg),
        SettingsSection(
          title: agentGeneral.sections.support,
          children: [
            if (!capabilities.usesCloudSessionModel)
              SettingsRow(
                key: const ValueKey('settings_about'),
                title: t.settings.about.title,
                body: t.settings.about.subtitle,
                trailing: ValueListenableBuilder<String?>(
                  valueListenable: UpdateBadgePrefs.value,
                  builder: (context, latestTag, child) {
                    final hasUpdate =
                        latestTag != null && latestTag.trim().isNotEmpty;
                    if (!hasUpdate) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      key: const ValueKey('settings_about_update_badge'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                ),
                showChevron: true,
                enabled: !_busy,
                onTap: () {
                  pushPageWithInheritedScopes(
                    Navigator.of(context),
                    context,
                    const AboutPage(),
                  );
                },
              ),
            SettingsRow(
              key: const ValueKey('settings_reopen_welcome_guide'),
              title: t.welcomeGuide.reopen.title,
              body: t.welcomeGuide.reopen.subtitle,
              showChevron: true,
              enabled: !_busy,
              onTap: () {
                pushPageWithInheritedScopes(
                  Navigator.of(context),
                  context,
                  WelcomePage(
                    onSkipForNow: () => Navigator.of(context).pop(),
                    onFinishSetup: () => Navigator.of(context).pop(),
                  ),
                );
              },
            ),
            SettingsRow(
              key: const ValueKey('settings_diagnostics'),
              title: t.settings.diagnostics.title,
              body: t.settings.diagnostics.subtitle,
              showChevron: true,
              enabled: !_busy,
              onTap: () {
                pushPageWithInheritedScopes(
                  Navigator.of(context),
                  context,
                  const DiagnosticsPage(),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
