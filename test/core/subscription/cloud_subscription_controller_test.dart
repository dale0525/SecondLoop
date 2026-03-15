import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/subscription/cloud_subscription_controller.dart';

void main() {
  test(
      'CloudSubscriptionController refreshes entitled status on web-safe client',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://gateway.test/v1/subscription');
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response(
        jsonEncode({
          'active': true,
          'can_manage_subscription': true,
        }),
        200,
      );
    });

    final controller = CloudSubscriptionController(
      idTokenGetter: () async => 'token-1',
      cloudGatewayBaseUrl: 'https://gateway.test',
      httpClient: client,
    );

    await controller.refresh();

    expect(controller.status, SubscriptionStatus.entitled);
    expect(controller.canManageSubscription, true);
  });

  test('CloudSubscriptionController refreshes not-entitled state', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'active': false,
          'can_manage_subscription': false,
        }),
        200,
      );
    });

    final controller = CloudSubscriptionController(
      idTokenGetter: () async => 'token-2',
      cloudGatewayBaseUrl: 'https://gateway.test',
      httpClient: client,
    );

    await controller.refresh();

    expect(controller.status, SubscriptionStatus.notEntitled);
    expect(controller.canManageSubscription, false);
  });
  test('CloudSubscriptionController exposes last refresh error', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'error': 'payment_required'}),
        402,
      );
    });

    final controller = CloudSubscriptionController(
      idTokenGetter: () async => 'token-3',
      cloudGatewayBaseUrl: 'https://gateway.test',
      httpClient: client,
    );

    await controller.refresh();

    expect(controller.status, SubscriptionStatus.unknown);
    expect(controller.lastRefreshError, isNotNull);
    expect(controller.lastRefreshError.toString(), contains('HTTP 402'));
    expect(
        controller.lastRefreshError.toString(), contains('payment_required'));
  });

  test('CloudSubscriptionController clears last refresh error after success',
      () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount += 1;
      if (callCount == 1) {
        return http.Response(
          jsonEncode({'error': 'payment_required'}),
          402,
        );
      }
      return http.Response(
        jsonEncode({
          'active': true,
          'can_manage_subscription': true,
        }),
        200,
      );
    });

    final controller = CloudSubscriptionController(
      idTokenGetter: () async => 'token-4',
      cloudGatewayBaseUrl: 'https://gateway.test',
      httpClient: client,
    );

    await controller.refresh();
    expect(controller.lastRefreshError, isNotNull);

    await controller.refresh();

    expect(controller.status, SubscriptionStatus.entitled);
    expect(controller.canManageSubscription, true);
    expect(controller.lastRefreshError, isNull);
  });
}
