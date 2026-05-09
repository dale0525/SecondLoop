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
