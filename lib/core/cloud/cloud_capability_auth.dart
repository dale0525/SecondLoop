import 'cloud_auth_access.dart';
import 'cloud_auth_controller.dart';

enum CloudCapabilityAuthMode {
  interactive,
  background,
}

Future<String?> readCloudCapabilityIdToken(
  CloudAuthController? controller, {
  required CloudCapabilityAuthMode mode,
}) {
  return readCloudAuthIdToken(
    controller,
    mode: switch (mode) {
      CloudCapabilityAuthMode.interactive => CloudAuthAccessMode.interactive,
      CloudCapabilityAuthMode.background => CloudAuthAccessMode.background,
    },
  );
}

Future<void> bestEffortWarmCloudCapabilityAuth(
  CloudAuthController? controller,
) {
  return bestEffortWarmCloudAuth(controller);
}
