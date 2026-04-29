part of 'settings_page.dart';

extension _SettingsPageBuild on _SettingsPageState {
  Widget _buildSettingsPage(BuildContext context) {
    final capabilities = AppPlatformCapabilityScope.of(context);
    final enabled = _appLockEnabled;
    final biometricEnabled = _biometricUnlockEnabled;
    final isMobile = capabilities.supportsBiometricUnlock &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    final supportsDesktopHotkey = capabilities.supportsDesktopHotkey;
    final supportsExternalImport = capabilities.supportsExternalImport;
    final supportsMigrationArchive = capabilities.supportsMigrationArchive;
    final supportsDesktopBootSettings =
        capabilities.supportsDesktopBootSettings;
    final supportsBiometricUnlock = capabilities.supportsBiometricUnlock;
    final showsAppearancePreferences =
        debugShowsAppearancePreferences(capabilities);
    final showsSecurityPreferences = !capabilities.usesCloudSessionModel;
    final isDesktop = supportsBiometricUnlock && !isMobile;
    final isZh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    final featureSettingsTitle = isZh ? '功能设置' : 'Feature settings';
    final systemUnlockSubtitleMobile = isZh
        ? '使用生物识别代替应用锁密码'
        : 'Unlock with biometrics instead of app lock password';
    final systemUnlockSubtitleDesktop = isZh
        ? '使用 Touch ID / Windows Hello 代替应用锁密码'
        : 'Unlock with Touch ID / Windows Hello instead of app lock password';

    Widget sectionCard(List<Widget> children) {
      return SlSurface(
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i != 0) const Divider(height: 1),
                children[i],
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.t.settings.sections.appearance,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        sectionCard([
          if (showsAppearancePreferences)
            ListTile(
              title: Text(context.t.settings.theme.title),
              subtitle: Text(context.t.settings.theme.subtitle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder(
                    valueListenable: AppThemeModePrefs.value,
                    builder: (context, mode, child) {
                      return Text(_themeModeLabel(context, mode));
                    },
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: _busy ? null : _selectThemeMode,
            ),
          if (showsAppearancePreferences)
            ListTile(
              key: const ValueKey('settings_theme_palette'),
              title: Text(_themePaletteTitle(context)),
              subtitle: Text(_themePaletteSubtitle(context)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder(
                    valueListenable: AppThemePalettePrefs.value,
                    builder: (context, palette, child) {
                      return Text(_themePaletteLabel(context, palette));
                    },
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: _busy ? null : _selectThemePalette,
            ),
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
        if (showsSecurityPreferences) ...[
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
            if ((enabled ?? false) &&
                supportsBiometricUnlock &&
                (isMobile || isDesktop))
              SwitchListTile(
                title: Text(
                  isMobile
                      ? context.t.settings.systemUnlock.titleMobile
                      : context.t.settings.systemUnlock.titleDesktop,
                ),
                subtitle: Text(
                  isMobile
                      ? systemUnlockSubtitleMobile
                      : systemUnlockSubtitleDesktop,
                ),
                value: biometricEnabled ?? false,
                onChanged: (_busy || biometricEnabled == null)
                    ? null
                    : _setBiometricUnlock,
              ),
            ListTile(
              title: Text(context.t.settings.lockNow.title),
              subtitle: Text(context.t.settings.lockNow.subtitle),
              onTap: _busy ? null : _lockNow,
            ),
          ]),
          const SizedBox(height: 16),
        ],
        Text(
          featureSettingsTitle,
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
                    pushPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const CloudAccountPage(),
                    );
                  },
          ),
          ListTile(
            key: const ValueKey('settings_ai_source'),
            title: Text(context.t.settings.aiSelection.title),
            subtitle: Text(context.t.settings.aiSelection.subtitle),
            onTap: _busy
                ? null
                : () {
                    pushPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const AiSettingsPage(),
                    );
                  },
          ),
          ListTile(
            title: Text(context.t.settings.sync.title),
            subtitle: Text(context.t.settings.sync.subtitle),
            onTap: _busy
                ? null
                : () {
                    pushPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const SyncSettingsPage(),
                    );
                  },
          ),
          ListTile(
            key: const ValueKey('settings_agent_digest'),
            title: Text(context.t.settings.agentDigest.title),
            subtitle: Text(context.t.settings.agentDigest.entrySubtitle),
            onTap: _busy
                ? null
                : () {
                    pushPageWithInheritedScopes(
                      Navigator.of(context),
                      context,
                      const AgentDigestSettingsPage(),
                    );
                  },
          ),
          if (supportsExternalImport)
            ListTile(
              key: const ValueKey('settings_external_import'),
              title: Text(context.t.settings.externalImport.title),
              subtitle: Text(context.t.settings.externalImport.introTitle),
              onTap: _busy
                  ? null
                  : () {
                      pushPageWithInheritedScopes(
                        Navigator.of(context),
                        context,
                        const ExternalImportPage(),
                      );
                    },
            ),
          if (supportsMigrationArchive)
            ListTile(
              key: const ValueKey('settings_migration_archive'),
              title: Text(context.t.settings.migrationArchive.title),
              subtitle: Text(context.t.settings.migrationArchive.subtitle),
              onTap: _busy
                  ? null
                  : () {
                      pushPageWithInheritedScopes(
                        Navigator.of(context),
                        context,
                        const MigrationArchivePage(),
                      );
                    },
            ),
          if (supportsDesktopBootSettings)
            SwitchListTile(
              key: const ValueKey('settings_start_with_system_switch'),
              title: Text(context.t.settings.desktopBoot.startWithSystem.title),
              subtitle:
                  Text(context.t.settings.desktopBoot.startWithSystem.subtitle),
              value: _desktopBootConfig.startWithSystem,
              onChanged: _busy ? null : _setDesktopStartWithSystem,
            ),
          if (supportsDesktopBootSettings)
            SwitchListTile(
              key: const ValueKey('settings_silent_startup_switch'),
              title: Text(context.t.settings.desktopBoot.silentStartup.title),
              subtitle:
                  Text(context.t.settings.desktopBoot.silentStartup.subtitle),
              value: _desktopBootConfig.silentStartup,
              onChanged: _busy ? null : _setDesktopSilentStartup,
            ),
          if (supportsDesktopBootSettings)
            SwitchListTile(
              key: const ValueKey('settings_keep_running_in_background_switch'),
              title: Text(
                  context.t.settings.desktopBoot.keepRunningInBackground.title),
              subtitle: Text(context
                  .t.settings.desktopBoot.keepRunningInBackground.subtitle),
              value: _desktopBootConfig.keepRunningInBackground,
              onChanged: _busy ? null : _setDesktopKeepRunningInBackground,
            ),
        ]),
        const SizedBox(height: 16),
        Text(
          context.t.settings.sections.support,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        sectionCard([
          if (!capabilities.usesCloudSessionModel)
            ListTile(
              key: const ValueKey('settings_about'),
              title: Text(context.t.settings.about.title),
              subtitle: Text(context.t.settings.about.subtitle),
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
          ListTile(
            key: const ValueKey('settings_reopen_welcome_guide'),
            title: Text(context.t.welcomeGuide.reopen.title),
            subtitle: Text(context.t.welcomeGuide.reopen.subtitle),
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
          ListTile(
            key: const ValueKey('settings_diagnostics'),
            title: Text(context.t.settings.diagnostics.title),
            subtitle: Text(context.t.settings.diagnostics.subtitle),
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
        Text(
          context.t.settings.sections.actions,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        sectionCard([
          SwitchListTile(
            key: const ValueKey(
                'settings_review_reminder_in_app_fallback_switch'),
            title: Text(context.t.settings.actionsReview.inAppFallback.title),
            subtitle:
                Text(context.t.settings.actionsReview.inAppFallback.subtitle),
            value: _reviewReminderInAppFallbackEnabled ??
                ReviewReminderInAppFallbackPrefs.defaultValue,
            onChanged: (_busy || _reviewReminderInAppFallbackEnabled == null)
                ? null
                : _setReviewReminderInAppFallback,
          ),
          if (supportsDesktopHotkey)
            ListTile(
              key: const ValueKey('settings_quick_capture_hotkey'),
              title: Text(context.t.settings.quickCaptureHotkey.title),
              subtitle: Text(context.t.settings.quickCaptureHotkey.subtitle),
              trailing: ValueListenableBuilder<HotKey?>(
                valueListenable: DesktopQuickCaptureHotkeyPrefs.value,
                builder: (context, override, child) {
                  final hotKey = override ??
                      _defaultQuickCaptureHotKey(defaultTargetPlatform);
                  return Text(_formatHotKey(hotKey));
                },
              ),
              onTap: _busy ? null : _editQuickCaptureHotkey,
            ),
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
              title: Text(context
                  .t.settingsReset.debugResetLocalDataThisDeviceOnly.title),
              subtitle: Text(context
                  .t.settingsReset.debugResetLocalDataThisDeviceOnly.subtitle),
              onTap: _busy
                  ? null
                  : () => _resetLocalData(clearAllRemoteData: false),
            ),
            ListTile(
              title: Text(
                  context.t.settingsReset.debugResetLocalDataAllDevices.title),
              subtitle: Text(context
                  .t.settingsReset.debugResetLocalDataAllDevices.subtitle),
              onTap: _busy
                  ? null
                  : () => _resetLocalData(clearAllRemoteData: true),
            ),
            ListTile(
              key: const ValueKey('settings_debug_run_oplog_maintenance'),
              title: Text(context.t.settings.debugOplogMaintenance.title),
              subtitle: Text(
                context.t.settings.debugOplogMaintenance.subtitle,
              ),
              onTap: _busy ? null : _runOplogMaintenanceDebug,
            ),
          ]),
        ],
      ],
    );
  }
}
