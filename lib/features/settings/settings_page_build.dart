part of 'settings_page.dart';

extension _SettingsPageBuild on _SettingsPageState {
  Widget _buildSettingsPage(BuildContext context) {
    final enabled = _appLockEnabled;
    final biometricEnabled = _biometricUnlockEnabled;
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    final supportsDesktopHotkey = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
    final isZh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    final featureSettingsTitle = isZh ? '功能设置' : 'Feature settings';

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
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CloudAccountPage(),
                      ),
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
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiSettingsPage(),
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
          if (supportsDesktopHotkey)
            SwitchListTile(
              key: const ValueKey('settings_start_with_system_switch'),
              title: Text(context.t.settings.desktopBoot.startWithSystem.title),
              subtitle:
                  Text(context.t.settings.desktopBoot.startWithSystem.subtitle),
              value: _desktopBootConfig.startWithSystem,
              onChanged: _busy ? null : _setDesktopStartWithSystem,
            ),
          if (supportsDesktopHotkey)
            SwitchListTile(
              key: const ValueKey('settings_silent_startup_switch'),
              title: Text(context.t.settings.desktopBoot.silentStartup.title),
              subtitle:
                  Text(context.t.settings.desktopBoot.silentStartup.subtitle),
              value: _desktopBootConfig.silentStartup,
              onChanged: _busy ? null : _setDesktopSilentStartup,
            ),
          if (supportsDesktopHotkey)
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
          ListTile(
            key: const ValueKey('settings_about'),
            title: Text(isZh ? '关于' : 'About'),
            subtitle:
                Text(isZh ? '项目主页、版本号与更新' : 'Homepage, version, and updates'),
            onTap: _busy
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AboutPage(),
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
