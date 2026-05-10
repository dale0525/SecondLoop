import 'package:http/http.dart' as http;

import 'runtime_connection_store.dart';
import 'runtime_manifest.dart';
import 'runtime_profile.dart';
import 'runtime_api_client.dart';
import 'secretary_runtime_client.dart';
import 'secretary_runtime_conversation_models.dart';

abstract interface class ChatRuntimeConversationSender {
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  });
}

final class SecretaryRuntimeConversationSender
    implements ChatRuntimeConversationSender {
  SecretaryRuntimeConversationSender({
    SecretaryRuntimeClient? client,
  }) : _client = client ?? SecretaryRuntimeClient();

  factory SecretaryRuntimeConversationSender.hostedManagedPro({
    required String apiBaseUrl,
    required Future<String?> Function() hostedSessionTokenGetter,
    http.Client? httpClient,
  }) {
    final normalizedBaseUrl = apiBaseUrl.trim();
    return SecretaryRuntimeConversationSender(
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
              ),
            );
          },
        ),
      ),
    );
  }

  final SecretaryRuntimeClient _client;

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    return _client.sendConversationMessage(
      vaultId,
      conversationId: conversationId,
      message: message,
    );
  }
}
