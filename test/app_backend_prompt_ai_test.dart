import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';

import 'test_backend.dart';

void main() {
  test('runAiPrompt uses a generic unimplemented error surface', () async {
    final backend = TestAppBackend();

    expect(
      () => backend.runAiPrompt(
        Uint8List.fromList(List<int>.filled(32, 1)),
        prompt: 'hello',
      ),
      throwsA(
        isA<UnimplementedError>().having(
          (error) => error.toString(),
          'message',
          contains('runAiPrompt'),
        ),
      ),
    );
  });

  test('runAiPrompt does not remap cloud-gateway unimplemented messages',
      () async {
    final backend = _CloudGatewayMessageBackend();

    expect(
      () => backend.runAiPrompt(
        Uint8List.fromList(List<int>.filled(32, 1)),
        prompt: 'hello',
      ),
      throwsA(
        isA<UnimplementedError>().having(
          (error) => error.toString(),
          'message',
          contains('taskPriorityRerankAiCloudGateway'),
        ),
      ),
    );
  });

  test('runAiPromptCloudGateway uses a generic unimplemented error surface',
      () async {
    final backend = TestAppBackend();

    expect(
      () => backend.runAiPromptCloudGateway(
        Uint8List.fromList(List<int>.filled(32, 1)),
        prompt: 'hello',
        gatewayBaseUrl: 'https://example.com',
        idToken: 'token',
        modelName: 'gpt-test',
      ),
      throwsA(
        isA<UnimplementedError>().having(
          (error) => error.toString(),
          'message',
          contains('runAiPromptCloudGateway'),
        ),
      ),
    );
  });
}

final class _CloudGatewayMessageBackend extends TestAppBackend {
  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) {
    throw UnimplementedError('taskPriorityRerankAiCloudGateway');
  }
}
