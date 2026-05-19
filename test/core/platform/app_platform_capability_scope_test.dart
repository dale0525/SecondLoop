import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';

void main() {
  testWidgets('capability scope returns injected web profile', (tester) async {
    late AppPlatformCapabilities resolved;

    await tester.pumpWidget(
      AppPlatformCapabilityScope(
        capabilities: AppPlatformCapabilities.webCloud(),
        child: Builder(
          builder: (context) {
            resolved = AppPlatformCapabilityScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolved.supportsDesktopHotkey, isFalse);
    expect(resolved.supportsAudioRecording, isFalse);
    expect(resolved.supportsDesktopDrop, isFalse);
    expect(resolved.usesCloudSessionModel, isTrue);
  });

  testWidgets('capability scope falls back to native profile', (tester) async {
    late AppPlatformCapabilities resolved;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          resolved = AppPlatformCapabilityScope.of(context);
          return const SizedBox.shrink();
        },
      ),
    );

    expect(resolved.usesCloudSessionModel, isFalse);
  });

  testWidgets('capability scope returns injected web native profile',
      (tester) async {
    late AppPlatformCapabilities resolved;

    await tester.pumpWidget(
      AppPlatformCapabilityScope(
        capabilities: AppPlatformCapabilities.webNative(),
        child: Builder(
          builder: (context) {
            resolved = AppPlatformCapabilityScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolved.supportsDesktopHotkey, isFalse);
    expect(resolved.supportsDesktopDrop, isFalse);
    expect(resolved.usesCloudSessionModel, isFalse);
  });

  test('platform capabilities compare by value', () {
    final usesCloudSessionModel = <bool>[true].single;
    final left = AppPlatformCapabilities(
      supportsDesktopHotkey: false,
      supportsAudioRecording: false,
      supportsDesktopDrop: false,
      supportsDesktopBootSettings: false,
      supportsCameraCapture: false,
      usesCloudSessionModel: usesCloudSessionModel,
    );
    final right = AppPlatformCapabilities(
      supportsDesktopHotkey: false,
      supportsAudioRecording: false,
      supportsDesktopDrop: false,
      supportsDesktopBootSettings: false,
      supportsCameraCapture: false,
      usesCloudSessionModel: usesCloudSessionModel,
    );

    expect(left, right);
    expect(left.hashCode, right.hashCode);
  });
}
