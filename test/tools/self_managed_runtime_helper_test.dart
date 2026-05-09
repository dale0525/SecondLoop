import 'package:flutter_test/flutter_test.dart';

import '../../tools/self_managed_runtime_helper.dart';
import '../../tools/self_managed_runtime_lib/deploy_runner.dart';

void main() {
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
    expect(output['auth_token'], 'runtime-token-openai');
    final verification = output['verification'] as Map<String, Object?>;
    expect(verification['ok'], isTrue);
  });
}
