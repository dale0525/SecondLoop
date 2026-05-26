import 'dart:convert';
import 'dart:io';

import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import 'self_managed_runtime_lib/cloudflare_auth.dart';
import 'self_managed_runtime_lib/deploy_runner.dart';
import 'self_managed_runtime_lib/uninstall_runner.dart';

Future<Map<String, Object?>> runSelfManagedRuntimeHelper({
  required Map<String, Object?> input,
  SelfManagedRuntimeDeployRunner? deployRunner,
  void Function(Map<String, Object?> event)? emitEvent,
}) async {
  final request = _setupRequestFromInput(input);
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
    'verification': result.verification?.toJson(),
  };
}

Future<Map<String, Object?>> runSelfManagedCloudflareAuthorizationHelper({
  required Map<String, Object?> input,
  SelfManagedCloudflareAuth? cloudflareAuth,
  void Function(Map<String, Object?> event)? emitEvent,
}) async {
  final auth = cloudflareAuth ?? SelfManagedCloudflareAuth();
  emitEvent?.call(<String, Object?>{
    'step': SelfManagedSetupStep.authorizing.name,
    'message': 'authorizing_cloudflare_oauth',
  });
  final result = await auth.authorize(
    '${input['cloudflare_account_label'] ?? ''}',
  );
  emitEvent?.call(<String, Object?>{
    'step': SelfManagedSetupStep.cloudflareReady.name,
    'message': 'cloudflare_oauth_ready',
  });
  return SelfManagedCloudflareAuthorizationResult(
    cloudflareAccountId: result.accountId,
    cloudflareAccountName: result.accountName,
    cloudflareUserEmail: result.userEmail,
  ).toJson();
}

Future<Map<String, Object?>> runSelfManagedRuntimeUninstallHelper({
  required Map<String, Object?> input,
  SelfManagedRuntimeUninstallRunner? uninstallRunner,
  void Function(Map<String, Object?> event)? emitEvent,
}) async {
  final request = _uninstallRequestFromInput(input);
  final runner = uninstallRunner ?? SelfManagedRuntimeUninstallRunner();
  final result = await runner.run(
    request,
    onProgress: (event) {
      emitEvent?.call(<String, Object?>{
        'step': event.step.name,
        'message': event.message,
      });
    },
  );
  return result.toJson();
}

Future<void> main(List<String> args) async {
  final raw = await stdin.transform(utf8.decoder).join();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final action = '${decoded['action'] ?? 'deploy'}'.trim().toLowerCase();
  final streamEvents = decoded['stream_events'] == true;
  void emitEvent(Map<String, Object?> event) {
    if (!streamEvents) return;
    stdout.writeln(jsonEncode(<String, Object?>{
      'event': 'progress',
      'progress': event,
    }));
  }

  try {
    final output = switch (action) {
      'authorize_cloudflare' =>
        await runSelfManagedCloudflareAuthorizationHelper(
          input: decoded,
          emitEvent: emitEvent,
        ),
      'uninstall' => await runSelfManagedRuntimeUninstallHelper(
          input: decoded,
          emitEvent: emitEvent,
        ),
      _ => await runSelfManagedRuntimeHelper(
          input: decoded,
          emitEvent: emitEvent,
        ),
    };
    if (streamEvents) {
      stdout.writeln(jsonEncode(<String, Object?>{
        'event': 'result',
        'result': output,
      }));
    } else {
      stdout.writeln(jsonEncode(output));
    }
  } on LocalRuntimeHelperException catch (error) {
    final output = <String, Object?>{
      'code': error.code,
      'message': error.message,
    };
    if (streamEvents) {
      stdout.writeln(jsonEncode(<String, Object?>{
        'event': 'error',
        'error': output,
      }));
    } else {
      stderr.writeln(jsonEncode(output));
    }
    exitCode = 1;
  }
}

SelfManagedSetupRequest _setupRequestFromInput(Map<String, Object?> input) {
  return SelfManagedSetupRequest(
    cloudflareAccountLabel: '${input['cloudflare_account_label'] ?? ''}',
    provider: '${input['provider'] ?? 'openai'}',
    apiKey: '${input['api_key'] ?? ''}',
    embeddingApiKey: '${input['embedding_api_key'] ?? ''}',
    multimodalApiKey: '${input['multimodal_api_key'] ?? ''}',
    requiresMultimodalLlm: input['requires_multimodal_llm'] is bool
        ? input['requires_multimodal_llm'] as bool
        : true,
    cloudflareAuthorizationMethod: _cloudflareAuthorizationMethod(input),
    cloudflareAccountId: '${input['cloudflare_account_id'] ?? ''}',
    cloudflareApiToken: '${input['cloudflare_api_token'] ?? ''}',
  );
}

SelfManagedRuntimeUninstallRequest _uninstallRequestFromInput(
  Map<String, Object?> input,
) {
  return SelfManagedRuntimeUninstallRequest(
    cloudflareAccountLabel: '${input['cloudflare_account_label'] ?? ''}',
    cloudflareAuthorizationMethod: _cloudflareAuthorizationMethod(input),
    cloudflareAccountId: '${input['cloudflare_account_id'] ?? ''}',
    cloudflareApiToken: '${input['cloudflare_api_token'] ?? ''}',
    runtimeId: '${input['runtime_id'] ?? ''}',
  );
}

SelfManagedCloudflareAuthorizationMethod _cloudflareAuthorizationMethod(
  Map<String, Object?> input,
) {
  return '${input['cloudflare_authorization_method'] ?? 'oauth'}' == 'manual'
      ? SelfManagedCloudflareAuthorizationMethod.manual
      : SelfManagedCloudflareAuthorizationMethod.oauth;
}
