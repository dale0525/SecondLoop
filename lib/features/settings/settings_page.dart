import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_controller.dart';
import '../../core/notifications/review_reminder_in_app_fallback_prefs.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/platform/app_platform_capabilities.dart';
import '../../core/platform/app_platform_capability_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../core/sync/vault_reset_error.dart';
import '../../core/desktop/desktop_boot_prefs.dart';
import '../../core/desktop/desktop_quick_capture_hotkey_prefs.dart';
import '../../core/update/update_badge_prefs.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../i18n/locale_prefs.dart';
import '../../i18n/strings.g.dart';
import '../actions/settings/actions_settings_store.dart';
import 'cloud_runtime_mode_page.dart';
import 'diagnostics_page.dart';
import 'about_page.dart';
import '../welcome/welcome_page.dart';
import 'settings_general_helpers.dart';
import 'settings_ui.dart';
import 'settings_theme_mode_row.dart';

part 'settings_page_build.dart';
part 'settings_page_reset_actions.dart';

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

  bool _isDesktopPlatform() {
    return AppPlatformCapabilityScope.of(context).supportsDesktopBootSettings;
  }

  @override
  void dispose() {
    _subscriptionController?.removeListener(_onSubscriptionChanged);
    _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
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

  String _currentLanguageLabel(BuildContext context) {
    return currentSettingsLanguageLabel(context, _localeOverride);
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

    _load();
    unawaited(_maybeDisableCloudEmbeddingsIfNotAllowed());

    if (AppPlatformCapabilityScope.of(context).supportsDesktopHotkey) {
      unawaited(DesktopQuickCaptureHotkeyPrefs.load());
    }
  }

  Future<void> _editQuickCaptureHotkey() async {
    if (_busy) return;
    await editSettingsQuickCaptureHotkey(context);
  }

  @override
  Widget build(BuildContext context) => _buildSettingsPage(context);
}
