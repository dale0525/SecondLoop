import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class DesktopBootConfig {
  const DesktopBootConfig({
    required this.startWithSystem,
    required this.silentStartup,
    required this.keepRunningInBackground,
  });

  static const defaults = DesktopBootConfig(
    startWithSystem: false,
    silentStartup: false,
    keepRunningInBackground: true,
  );

  final bool startWithSystem;
  final bool silentStartup;
  final bool keepRunningInBackground;

  DesktopBootConfig copyWith({
    bool? startWithSystem,
    bool? silentStartup,
    bool? keepRunningInBackground,
  }) {
    return DesktopBootConfig(
      startWithSystem: startWithSystem ?? this.startWithSystem,
      silentStartup: silentStartup ?? this.silentStartup,
      keepRunningInBackground:
          keepRunningInBackground ?? this.keepRunningInBackground,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DesktopBootConfig &&
        other.startWithSystem == startWithSystem &&
        other.silentStartup == silentStartup &&
        other.keepRunningInBackground == keepRunningInBackground;
  }

  @override
  int get hashCode => Object.hash(
        startWithSystem,
        silentStartup,
        keepRunningInBackground,
      );
}

final class DesktopBootPrefs {
  static const startWithSystemKey = 'desktop.start_with_system_v1';
  static const silentStartupKey = 'desktop.silent_startup_v1';
  static const keepRunningInBackgroundKey =
      'desktop.keep_running_in_background_v1';

  static final ValueNotifier<DesktopBootConfig> value =
      ValueNotifier<DesktopBootConfig>(DesktopBootConfig.defaults);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value.value = DesktopBootConfig(
      startWithSystem: prefs.getBool(startWithSystemKey) ??
          DesktopBootConfig.defaults.startWithSystem,
      silentStartup: prefs.getBool(silentStartupKey) ??
          DesktopBootConfig.defaults.silentStartup,
      keepRunningInBackground: prefs.getBool(keepRunningInBackgroundKey) ??
          DesktopBootConfig.defaults.keepRunningInBackground,
    );
  }

  static Future<void> setStartWithSystem(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(startWithSystemKey, enabled);
    value.value = value.value.copyWith(startWithSystem: enabled);
  }

  static Future<void> setSilentStartup(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(silentStartupKey, enabled);
    value.value = value.value.copyWith(silentStartup: enabled);
  }

  static Future<void> setKeepRunningInBackground(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keepRunningInBackgroundKey, enabled);
    value.value = value.value.copyWith(keepRunningInBackground: enabled);
  }
}
