import 'package:flutter/foundation.dart';

@immutable
class AppPlatformCapabilities {
  const AppPlatformCapabilities({
    required this.supportsDesktopHotkey,
    required this.supportsBiometricUnlock,
    required this.supportsMigrationArchive,
    required this.supportsAudioRecording,
    required this.supportsDesktopDrop,
    required this.supportsExternalImport,
    required this.supportsDesktopBootSettings,
    required this.supportsCameraCapture,
    required this.usesCloudSessionModel,
  });

  factory AppPlatformCapabilities.native() {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return AppPlatformCapabilities(
      supportsDesktopHotkey: isDesktop,
      supportsBiometricUnlock: !kIsWeb &&
          (isMobile ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows),
      supportsMigrationArchive: !kIsWeb,
      supportsAudioRecording: !kIsWeb &&
          (isMobile ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows),
      supportsDesktopDrop: isDesktop,
      supportsExternalImport: isDesktop,
      supportsDesktopBootSettings: isDesktop,
      supportsCameraCapture: isMobile,
      usesCloudSessionModel: false,
    );
  }

  factory AppPlatformCapabilities.webCloud() {
    return const AppPlatformCapabilities(
      supportsDesktopHotkey: false,
      supportsBiometricUnlock: false,
      supportsMigrationArchive: false,
      supportsAudioRecording: false,
      supportsDesktopDrop: false,
      supportsExternalImport: false,
      supportsDesktopBootSettings: false,
      supportsCameraCapture: false,
      usesCloudSessionModel: true,
    );
  }

  final bool supportsDesktopHotkey;
  final bool supportsBiometricUnlock;
  final bool supportsMigrationArchive;
  final bool supportsAudioRecording;
  final bool supportsDesktopDrop;
  final bool supportsExternalImport;
  final bool supportsDesktopBootSettings;
  final bool supportsCameraCapture;
  final bool usesCloudSessionModel;
}
