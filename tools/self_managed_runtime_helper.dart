import 'dart:convert';
import 'dart:io';

import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import 'self_managed_runtime_lib/deploy_runner.dart';

Future<Map<String, Object?>> runSelfManagedRuntimeHelper({
  required Map<String, Object?> input,
  SelfManagedRuntimeDeployRunner? deployRunner,
  void Function(Map<String, Object?> event)? emitEvent,
}) async {
  final request = SelfManagedSetupRequest(
    cloudflareAccountLabel: '${input['cloudflare_account_label'] ?? ''}',
    provider: '${input['provider'] ?? 'openai'}',
    apiKey: '${input['api_key'] ?? ''}',
    embeddingApiKey: '${input['embedding_api_key'] ?? ''}',
    multimodalApiKey: '${input['multimodal_api_key'] ?? ''}',
    requiresMultimodalLlm: input['requires_multimodal_llm'] is bool
        ? input['requires_multimodal_llm'] as bool
        : true,
  );
  final runner = deployRunner ?? SelfManagedRuntimeDeployRunner();
  final result = await runner.run(
    request,
    onProgress: (event) {
      emitEvent?.call(<String, Object?>{
        'step': event.step.name,
        'message': event.message,
      });
    },
  );
  return <String, Object?>{
    'manifest': result.manifest.toJson(),
    'auth_token': result.authToken,
    'capability_manifest_id': result.capabilityManifestId,
  };
}

Future<void> main(List<String> args) async {
  final raw = await stdin.transform(utf8.decoder).join();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final output = await runSelfManagedRuntimeHelper(input: decoded);
  stdout.writeln(jsonEncode(output));
}
