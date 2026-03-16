import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HttpJsonClient keeps injected http clients strongly typed', () {
    final httpJsonClient =
        File('lib/core/cloud/http_json_client.dart').readAsStringSync();
    final cloudUsageClient =
        File('lib/core/cloud/cloud_usage_client.dart').readAsStringSync();
    final vaultUsageClient =
        File('lib/core/cloud/vault_usage_client.dart').readAsStringSync();
    final vaultAttachmentsClient =
        File('lib/core/cloud/vault_attachments_client.dart').readAsStringSync();
    final subscriptionController =
        File('lib/core/subscription/cloud_subscription_controller.dart')
            .readAsStringSync();
    final billingClient =
        File('lib/core/subscription/creem_billing_client.dart')
            .readAsStringSync();

    expect(httpJsonClient, contains('final http.Client _client;'));
    expect(httpJsonClient, isNot(contains('as dynamic')));
    expect(cloudUsageClient, isNot(contains('Object? httpClient')));
    expect(vaultUsageClient, isNot(contains('Object? httpClient')));
    expect(vaultAttachmentsClient, isNot(contains('Object? httpClient')));
    expect(subscriptionController, isNot(contains('Object? httpClient')));
    expect(billingClient, isNot(contains('Object? httpClient')));
  });
}
