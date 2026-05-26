import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import '../../tools/self_managed_runtime_helper.dart';
import '../../tools/self_managed_runtime_lib/cloudflare_auth.dart';
import '../../tools/self_managed_runtime_lib/deploy_runner.dart';
import '../../tools/self_managed_runtime_lib/uninstall_runner.dart';

void main() {
  test('pixi helper task bypasses the FVM wrapper for stdin safety', () {
    final pixi = File('pixi.toml').readAsStringSync();

    expect(
      pixi,
      contains(
        'self-managed-runtime-helper = ".fvm/flutter_sdk/bin/dart run tools/self_managed_runtime_helper.dart"',
      ),
    );
    expect(
      pixi,
      contains(
        'self-managed-runtime-helper = ".fvm\\\\flutter_sdk\\\\bin\\\\dart.bat run tools/self_managed_runtime_helper.dart"',
      ),
    );
    expect(
      pixi,
      isNot(
        contains(
          'self-managed-runtime-helper = "dart pub global run fvm:main',
        ),
      ),
    );
  });

  test('helper emits manifest payload and progress events', () async {
    final events = <Map<String, Object?>>[];
    final output = await runSelfManagedRuntimeHelper(
      input: <String, Object?>{
        'cloudflare_account_label': 'acct-1',
        'provider': 'openai',
        'api_key': 'sk-test',
        'embedding_api_key': 'emb-test',
        'multimodal_api_key': 'mm-test',
      },
      deployRunner: SelfManagedRuntimeDeployRunner(
        cloudflareAuth: SelfManagedCloudflareAuth(
          authorize: (accountLabel) async =>
              SelfManagedCloudflareAuthorization.placeholder(
            accessToken: 'cf-token-$accountLabel',
            accountLabel: accountLabel,
          ),
        ),
        postVerificationJson: (_, __) async => <String, Object?>{
          'ok': true,
          'checks': [
            <String, Object?>{
              'code': 'structured_output',
              'passed': true,
            },
          ],
        },
      ),
      emitEvent: events.add,
    );

    expect(events, isNotEmpty);
    final manifest = output['manifest'] as Map<String, Object?>;
    expect(manifest['runtime_mode'], 'self_managed');
    final skills = manifest['skills'] as List<Object?>;
    expect(skills.single, <String, Object?>{
      'id': 'web-research',
      'status': 'ready',
      'provider': 'configured',
    });
    expect(output['auth_token'], 'runtime-token-openai');
    final verification = output['verification'] as Map<String, Object?>;
    expect(verification['ok'], isTrue);
  });

  test('Cloudflare OAuth helper returns account metadata without token',
      () async {
    final events = <Map<String, Object?>>[];
    final output = await runSelfManagedCloudflareAuthorizationHelper(
      input: <String, Object?>{
        'action': 'authorize_cloudflare',
        'cloudflare_account_label': 'acct-1',
      },
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (_) async => const SelfManagedCloudflareAuthorization(
          accessToken: 'oauth-session-token',
          accountId: 'acct-1',
          accountName: 'Personal Account',
          userEmail: 'user@example.test',
        ),
      ),
      emitEvent: events.add,
    );

    expect(events.map((event) => event['step']), [
      'authorizing',
      'cloudflareReady',
    ]);
    expect(output['cloudflare_account_id'], 'acct-1');
    expect(output['cloudflare_account_name'], 'Personal Account');
    expect(output['cloudflare_user_email'], 'user@example.test');
    expect(output.toString().contains('oauth-session-token'), isFalse);
  });

  test('uninstall helper emits summary payload and progress events', () async {
    final events = <Map<String, Object?>>[];
    final output = await runSelfManagedRuntimeUninstallHelper(
      input: <String, Object?>{
        'action': 'uninstall',
        'cloudflare_authorization_method': 'manual',
        'cloudflare_account_id': 'acct-1',
        'cloudflare_api_token': 'cf-session-token',
      },
      uninstallRunner: SelfManagedRuntimeUninstallRunner(
        uninstallResources: (request, _, plan) async {
          return SelfManagedRuntimeUninstallResult(
            ok: true,
            runtimeMode: 'self_managed',
            cloudflareAccountId: request.cloudflareDeploymentAccountId,
            removedWorkers: plan.workerNames,
            removedBindings: plan.bindings,
            removedSecrets: plan.secrets,
          );
        },
      ),
      emitEvent: events.add,
    );

    expect(
      events.map((event) => event['step']),
      ['authorizing', 'uninstalling', 'uninstalled'],
    );
    expect(output['ok'], isTrue);
    expect(output['runtime_mode'], 'self_managed');
    expect(output['cloudflare_account_id'], 'acct-1');
    expect(output['removed_workers'], contains('secretary-runtime'));
    expect(output['removed_bindings'], contains('D1'));
    expect(output['removed_secrets'], contains('LLM_API_KEY'));
    expect(output.toString().contains('cf-session-token'), isFalse);
  });
}
