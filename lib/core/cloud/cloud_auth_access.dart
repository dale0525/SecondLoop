import 'cloud_auth_controller.dart';

enum CloudAuthAccessMode {
  interactive,
  background,
}

Future<String?> readCloudAuthIdToken(
  CloudAuthController? controller, {
  required CloudAuthAccessMode mode,
}) async {
  if (controller == null) return null;

  try {
    switch (mode) {
      case CloudAuthAccessMode.interactive:
        return await controller.getIdToken();
      case CloudAuthAccessMode.background:
        return await readCloudIdTokenForBackground(controller);
    }
  } catch (_) {
    return null;
  }
}

Future<void> bestEffortWarmCloudAuth(CloudAuthController? controller) async {
  await readCloudAuthIdToken(
    controller,
    mode: CloudAuthAccessMode.interactive,
  );
}
