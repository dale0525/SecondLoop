import 'runtime_connection_store.dart';
import 'runtime_manifest.dart';
import 'runtime_profile.dart';

final class RuntimeTestProfileInjector {
  RuntimeTestProfileInjector({
    RuntimeConnectionStore? connectionStore,
  }) : _connectionStore = connectionStore ?? RuntimeConnectionStore();

  final RuntimeConnectionStore _connectionStore;

  Future<void> injectSelfManaged({
    required String apiBaseUrl,
    String authToken = 'runtime-test-token',
    String capabilityManifestId = 'runtime-test-manifest',
    List<CloudRuntimeCapability> capabilities = const [
      ...CloudRuntimeRequiredCapabilities.all,
      CloudRuntimeCapability('runtime_test_api'),
    ],
  }) {
    return _connectionStore.saveConnection(
      CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: apiBaseUrl,
          authMode: CloudRuntimeAuthMode.runtimeToken,
          authToken: authToken,
          capabilityManifestId: capabilityManifestId,
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.selfManaged,
          apiBaseUrl: apiBaseUrl,
          authMode: CloudRuntimeAuthMode.runtimeToken,
          capabilities: capabilities,
        ),
      ),
    );
  }

  Future<void> injectManagedPro({
    required String apiBaseUrl,
    String authToken = 'managed-session-token',
    String capabilityManifestId = 'managed-runtime-manifest',
    List<CloudRuntimeCapability> capabilities = const [
      ...CloudRuntimeRequiredCapabilities.all,
      CloudRuntimeCapability('runtime_test_api'),
    ],
  }) {
    return _connectionStore.saveConnection(
      CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: apiBaseUrl,
          authMode: CloudRuntimeAuthMode.hostedSession,
          authToken: authToken,
          capabilityManifestId: capabilityManifestId,
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: apiBaseUrl,
          authMode: CloudRuntimeAuthMode.hostedSession,
          capabilities: capabilities,
        ),
      ),
    );
  }

  Future<void> clear() {
    return _connectionStore.clearConnection();
  }
}
