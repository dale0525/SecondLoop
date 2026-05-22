import 'package:http/http.dart' as http;

import 'runtime_agent_state_models.dart';
import 'runtime_api_client.dart';
import 'runtime_connection_store.dart';
import 'runtime_manifest.dart';
import 'runtime_profile.dart';
import 'secretary_runtime_client.dart';

abstract interface class RuntimeAgentStateRepository {
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  });
}

final class SecretaryRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  SecretaryRuntimeAgentStateRepository({
    SecretaryRuntimeClient? client,
  }) : _client = client ?? SecretaryRuntimeClient();

  factory SecretaryRuntimeAgentStateRepository.hostedManagedPro({
    required String apiBaseUrl,
    required Future<String?> Function() hostedSessionTokenGetter,
    http.Client? httpClient,
  }) {
    final normalizedBaseUrl = apiBaseUrl.trim();
    return SecretaryRuntimeAgentStateRepository(
      client: SecretaryRuntimeClient(
        apiClient: RuntimeApiClient(
          httpClient: httpClient,
          connectionLoader: () async {
            final token = (await hostedSessionTokenGetter())?.trim() ?? '';
            if (normalizedBaseUrl.isEmpty || token.isEmpty) {
              return null;
            }
            return CloudRuntimeConnection(
              profile: CloudRuntimeProfile(
                runtimeMode: CloudRuntimeMode.managedPro,
                apiBaseUrl: normalizedBaseUrl,
                authMode: CloudRuntimeAuthMode.hostedSession,
                authToken: token,
                capabilityManifestId: 'managed-pro-runtime',
                manifestVersion:
                    RuntimeConnectionStore.supportedManifestVersion,
              ),
              manifest: CloudRuntimeManifest(
                manifestVersion:
                    RuntimeConnectionStore.supportedManifestVersion,
                runtimeMode: CloudRuntimeMode.managedPro,
                apiBaseUrl: normalizedBaseUrl,
                authMode: CloudRuntimeAuthMode.hostedSession,
                capabilities: CloudRuntimeRequiredCapabilities.all,
                skills: CloudRuntimeKnownSkills.all,
              ),
            );
          },
        ),
      ),
    );
  }

  final SecretaryRuntimeClient _client;

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) {
    return _client.fetchAgentState(
      vaultId,
      conversationId: conversationId,
      turnLimit: turnLimit,
      turnBefore: turnBefore,
      turnOrder: turnOrder,
    );
  }
}
