import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';

CloudRuntimeManifest buildSelfManagedRuntimeManifest({
  required String apiBaseUrl,
  List<CloudRuntimeCapability> capabilities = const [
    ...CloudRuntimeRequiredCapabilities.all,
    CloudRuntimeCapability('deployment_test_api'),
    CloudRuntimeCapability('runtime_test_api'),
  ],
  List<CloudRuntimeSkillAvailability> skills = CloudRuntimeKnownSkills.all,
}) {
  return CloudRuntimeManifest(
    manifestVersion: 1,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: apiBaseUrl,
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: capabilities,
    skills: skills,
  );
}
