part of 'app_backend.dart';

extension AppBackendPromptAi on AppBackend {
  Future<String> runTodoFollowupPrompt(
    Uint8List key, {
    required String prompt,
    required String generationModeWireValue,
  }) {
    return runAiPrompt(
      key,
      prompt: encodeTodoFollowupPromptEnvelope(
        prompt,
        generationModeWireValue: generationModeWireValue,
      ),
    );
  }

  Future<String> runTodoFollowupPromptCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String generationModeWireValue,
  }) {
    return _runTodoFollowupPromptCloudGateway(
      key,
      prompt: encodeTodoFollowupPromptEnvelope(
        prompt,
        generationModeWireValue: generationModeWireValue,
      ),
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: modelName,
    );
  }

  Future<String> _runTodoFollowupPromptCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    try {
      return await todoFollowupRerankAiCloudGateway(
        key,
        prompt: prompt,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        modelName: modelName,
      );
    } on UnimplementedError catch (error, stackTrace) {
      final message = error.toString();
      if (message.contains('todoFollowupRerankAiCloudGateway')) {
        Error.throwWithStackTrace(
          UnimplementedError(
            'runTodoFollowupPromptCloudGateway / todoFollowupRerankAiCloudGateway',
          ),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<String> runAiPrompt(
    Uint8List key, {
    required String prompt,
  }) async {
    try {
      return await taskPriorityRerankAi(
        key,
        prompt: prompt,
      );
    } on UnimplementedError catch (error, stackTrace) {
      final message = error.toString();
      if (message.contains('taskPriorityRerankAi') &&
          !message.contains('taskPriorityRerankAiCloudGateway')) {
        Error.throwWithStackTrace(
          UnimplementedError('runAiPrompt / taskPriorityRerankAi'),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<String> runAiPromptCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    try {
      return await taskPriorityRerankAiCloudGateway(
        key,
        prompt: prompt,
        gatewayBaseUrl: gatewayBaseUrl,
        idToken: idToken,
        modelName: modelName,
      );
    } on UnimplementedError catch (error, stackTrace) {
      final message = error.toString();
      if (message.contains('taskPriorityRerankAiCloudGateway')) {
        Error.throwWithStackTrace(
          UnimplementedError(
            'runAiPromptCloudGateway / taskPriorityRerankAiCloudGateway',
          ),
          stackTrace,
        );
      }
      rethrow;
    }
  }
}
