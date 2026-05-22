part of 'settings_page.dart';

extension _SettingsPageBuild on _SettingsPageState {
  Widget _buildSettingsPage(BuildContext context) {
    final capabilities = AppPlatformCapabilityScope.of(context);
    final supportsDesktopHotkey = capabilities.supportsDesktopHotkey;
    final supportsDesktopBootSettings =
        capabilities.supportsDesktopBootSettings;
    final showsAppearancePreferences =
        debugShowsAppearancePreferences(capabilities);
    final isZh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    final featureSettingsTitle = isZh ? '功能设置' : 'Feature settings';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsSection(
            title: context.t.settings.sections.appearance,
            children: [
              if (showsAppearancePreferences)
                SettingsRow(
                  title: context.t.settings.theme.title,
                  body: context.t.settings.theme.subtitle,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder(
                        valueListenable: AppThemeModePrefs.value,
                        builder: (context, mode, child) {
                          return Text(_themeModeLabel(context, mode));
                        },
                      ),
                    ],
                  ),
                  showChevron: true,
                  onTap: _busy ? null : _selectThemeMode,
                ),
              if (showsAppearancePreferences)
                SettingsRow(
                  key: const ValueKey('settings_theme_palette'),
                  title: _themePaletteTitle(context),
                  body: _themePaletteSubtitle(context),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder(
                        valueListenable: AppThemePalettePrefs.value,
                        builder: (context, palette, child) {
                          return Text(_themePaletteLabel(context, palette));
                        },
                      ),
                    ],
                  ),
                  showChevron: true,
                  onTap: _busy ? null : _selectThemePalette,
                ),
              SettingsRow(
                title: context.t.settings.language.title,
                body: context.t.settings.language.subtitle,
                trailing: Text(_currentLanguageLabel(context)),
                showChevron: true,
                onTap: _busy ? null : _selectLanguage,
              ),
            ]),
        const SizedBox(height: 16),
        SettingsSection(title: featureSettingsTitle, children: [
          SettingsRow(
            key: const ValueKey('settings_runtime_mode'),
            title: context.t.settings.runtimeMode.title,
            body: context.t.settings.runtimeMode.subtitle,
            showChevron: true,
            onTap: _busy
                ? null
                : () {
                    pushPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const CloudRuntimeModePage(),
                    );
                  },
          ),
          if (supportsDesktopBootSettings)
            SettingsSwitchRow(
              key: const ValueKey('settings_start_with_system_switch'),
              title: context.t.settings.desktopBoot.startWithSystem.title,
              body: context.t.settings.desktopBoot.startWithSystem.subtitle,
              value: _desktopBootConfig.startWithSystem,
              onChanged: _busy ? null : _setDesktopStartWithSystem,
            ),
          if (supportsDesktopBootSettings)
            SettingsSwitchRow(
              key: const ValueKey('settings_silent_startup_switch'),
              title: context.t.settings.desktopBoot.silentStartup.title,
              body: context.t.settings.desktopBoot.silentStartup.subtitle,
              value: _desktopBootConfig.silentStartup,
              onChanged: _busy ? null : _setDesktopSilentStartup,
            ),
          if (supportsDesktopBootSettings)
            SettingsSwitchRow(
              key: const ValueKey('settings_keep_running_in_background_switch'),
              title:
                  context.t.settings.desktopBoot.keepRunningInBackground.title,
              body: context
                  .t.settings.desktopBoot.keepRunningInBackground.subtitle,
              value: _desktopBootConfig.keepRunningInBackground,
              onChanged: _busy ? null : _setDesktopKeepRunningInBackground,
            ),
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: context.t.settings.sections.support, children: [
          if (!capabilities.usesCloudSessionModel)
            SettingsRow(
              key: const ValueKey('settings_about'),
              title: context.t.settings.about.title,
              body: context.t.settings.about.subtitle,
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
              onTap: _busy
                  ? null
                  : () {
                      pushPageWithInheritedScopes(
                        Navigator.of(context),
                        context,
                        const AboutPage(),
                      );
                    },
            ),
          SettingsRow(
            key: const ValueKey('settings_reopen_welcome_guide'),
            title: context.t.welcomeGuide.reopen.title,
            body: context.t.welcomeGuide.reopen.subtitle,
            showChevron: true,
            onTap: _busy
                ? null
                : () {
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
            title: context.t.settings.diagnostics.title,
            body: context.t.settings.diagnostics.subtitle,
            showChevron: true,
            onTap: _busy
                ? null
                : () {
                    pushPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const DiagnosticsPage(),
                    );
                  },
          ),
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: context.t.settings.sections.actions, children: [
          SettingsSwitchRow(
            key: const ValueKey(
                'settings_review_reminder_in_app_fallback_switch'),
            title: context.t.settings.actionsReview.inAppFallback.title,
            body: context.t.settings.actionsReview.inAppFallback.subtitle,
            value: _reviewReminderInAppFallbackEnabled ??
                ReviewReminderInAppFallbackPrefs.defaultValue,
            onChanged: (_busy || _reviewReminderInAppFallbackEnabled == null)
                ? null
                : _setReviewReminderInAppFallback,
          ),
          if (supportsDesktopHotkey)
            SettingsRow(
              key: const ValueKey('settings_quick_capture_hotkey'),
              title: context.t.settings.quickCaptureHotkey.title,
              body: context.t.settings.quickCaptureHotkey.subtitle,
              trailing: ValueListenableBuilder<HotKey?>(
                valueListenable: DesktopQuickCaptureHotkeyPrefs.value,
                builder: (context, override, child) {
                  final hotKey = override ??
                      _defaultQuickCaptureHotKey(defaultTargetPlatform);
                  return Text(_formatHotKey(hotKey));
                },
              ),
              showChevron: true,
              onTap: _busy ? null : _editQuickCaptureHotkey,
            ),
          SettingsRow(
            title: context.t.settings.actionsReview.morningTime.title,
            body: context.t.settings.actionsReview.morningTime.subtitle,
            trailing:
                Text(_actionsSettings?.morningTime.format(context) ?? '—'),
            showChevron: true,
            onTap: (_busy || _actionsSettings == null)
                ? null
                : () => _pickActionsTime(
                      initial: _actionsSettings!.morningTime,
                      persist: ActionsSettingsStore.setMorningTime,
                    ),
          ),
          SettingsRow(
            title: context.t.settings.actionsReview.dayEndTime.title,
            body: context.t.settings.actionsReview.dayEndTime.subtitle,
            trailing: Text(_actionsSettings?.dayEndTime.format(context) ?? '—'),
            showChevron: true,
            onTap: (_busy || _actionsSettings == null)
                ? null
                : () => _pickActionsTime(
                      initial: _actionsSettings!.dayEndTime,
                      persist: ActionsSettingsStore.setDayEndTime,
                    ),
          ),
          SettingsRow(
            title: context.t.settings.actionsReview.weeklyTime.title,
            body: context.t.settings.actionsReview.weeklyTime.subtitle,
            trailing:
                Text(_actionsSettings?.weeklyReviewTime.format(context) ?? '—'),
            showChevron: true,
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
          SettingsSection(title: context.t.settings.sections.debug, children: [
            SettingsRow(
              key: const ValueKey(
                'settings_debug_reset_local_data_this_device',
              ),
              title: context
                  .t.settingsReset.debugResetLocalDataThisDeviceOnly.title,
              body: context
                  .t.settingsReset.debugResetLocalDataThisDeviceOnly.subtitle,
              showChevron: true,
              onTap: _busy
                  ? null
                  : () => _resetLocalData(
                        variant: _ResetLocalDataVariant.thisDeviceOnly,
                      ),
            ),
            SettingsRow(
              key: const ValueKey(
                'settings_debug_reset_local_data_runtime_hosted_data_unchanged',
              ),
              title: context.t.settingsReset
                  .debugResetLocalDataRuntimeHostedDataUnchanged.title,
              body: context.t.settingsReset
                  .debugResetLocalDataRuntimeHostedDataUnchanged.subtitle,
              showChevron: true,
              onTap: _busy
                  ? null
                  : () => _resetLocalData(
                        variant:
                            _ResetLocalDataVariant.runtimeHostedDataUnchanged,
                      ),
            ),
          ]),
        ],
      ],
    );
  }
}
