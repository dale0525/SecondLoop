import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';

CloudRuntimeManifest buildSelfManagedRuntimeManifest({
  required String apiBaseUrl,
  List<CloudRuntimeCapability> capabilities = const [
    CloudRuntimeCapability('chat'),
    CloudRuntimeCapability('working_set'),
    CloudRuntimeCapability('deployment_test_api'),
    CloudRuntimeCapability('runtime_test_api'),
  ],
}) {
  return CloudRuntimeManifest(
    manifestVersion: 1,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: apiBaseUrl,
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: capabilities,
  );
}
