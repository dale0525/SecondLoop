import 'package:flutter/foundation.dart';

@immutable
class AppPlatformCapabilities {
  const AppPlatformCapabilities({
    required this.supportsDesktopHotkey,
    required this.supportsAudioRecording,
    required this.supportsDesktopDrop,
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
      supportsAudioRecording: !kIsWeb &&
          (isMobile ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows),
      supportsDesktopDrop: isDesktop,
      supportsDesktopBootSettings: isDesktop,
      supportsCameraCapture: isMobile,
      usesCloudSessionModel: false,
    );
  }

  factory AppPlatformCapabilities.webCloud() {
    return const AppPlatformCapabilities(
      supportsDesktopHotkey: false,
      supportsAudioRecording: false,
      supportsDesktopDrop: false,
      supportsDesktopBootSettings: false,
      supportsCameraCapture: false,
      usesCloudSessionModel: true,
    );
  }

  factory AppPlatformCapabilities.webNative() {
    return const AppPlatformCapabilities(
      supportsDesktopHotkey: false,
      supportsAudioRecording: false,
      supportsDesktopDrop: false,
      supportsDesktopBootSettings: false,
      supportsCameraCapture: false,
      usesCloudSessionModel: false,
    );
  }

  final bool supportsDesktopHotkey;
  final bool supportsAudioRecording;
  final bool supportsDesktopDrop;
  final bool supportsDesktopBootSettings;
  final bool supportsCameraCapture;
  final bool usesCloudSessionModel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppPlatformCapabilities &&
        other.supportsDesktopHotkey == supportsDesktopHotkey &&
        other.supportsAudioRecording == supportsAudioRecording &&
        other.supportsDesktopDrop == supportsDesktopDrop &&
        other.supportsDesktopBootSettings == supportsDesktopBootSettings &&
        other.supportsCameraCapture == supportsCameraCapture &&
        other.usesCloudSessionModel == usesCloudSessionModel;
  }

  @override
  int get hashCode => Object.hash(
        supportsDesktopHotkey,
        supportsAudioRecording,
        supportsDesktopDrop,
        supportsDesktopBootSettings,
        supportsCameraCapture,
        usesCloudSessionModel,
      );
}
