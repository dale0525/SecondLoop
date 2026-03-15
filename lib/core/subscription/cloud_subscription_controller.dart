import 'package:flutter/foundation.dart';

import '../ai/ai_routing.dart';
import '../cloud/http_json_client.dart';
import 'subscription_scope.dart';

final class _CloudSubscriptionSnapshot {
  const _CloudSubscriptionSnapshot({
    required this.status,
    required this.canManageSubscription,
  });

  final SubscriptionStatus status;
  final bool? canManageSubscription;
}

final class CloudSubscriptionController extends ChangeNotifier
    implements SubscriptionDetailsController {
  CloudSubscriptionController({
    required Future<String?> Function() idTokenGetter,
    required String cloudGatewayBaseUrl,
    Object? httpClient,
  })  : _idTokenGetter = idTokenGetter,
        _cloudGatewayBaseUrl = cloudGatewayBaseUrl,
        _httpClient = HttpJsonClient(client: httpClient);

  final Future<String?> Function() _idTokenGetter;
  final String _cloudGatewayBaseUrl;
  final HttpJsonClient _httpClient;

  SubscriptionStatus _status = SubscriptionStatus.unknown;
  @override
  SubscriptionStatus get status => _status;

  bool? _canManageSubscription;

  @override
  bool? get canManageSubscription => _canManageSubscription;

  Object? _lastRefreshError;
  Object? get lastRefreshError => _lastRefreshError;

  Future<void> refresh() async {
    final next = await _refreshFromCloudGateway();
    if (next == null) return;

    _setState(
      status: next.status,
      canManageSubscription: next.canManageSubscription,
    );
  }

  Future<_CloudSubscriptionSnapshot?> _refreshFromCloudGateway() async {
    if (_cloudGatewayBaseUrl.trim().isEmpty) {
      _lastRefreshError = null;
      return null;
    }

    String? idToken;
    try {
      idToken = await _idTokenGetter();
    } catch (_) {
      _lastRefreshError = null;
      return null;
    }
    if (idToken == null || idToken.trim().isEmpty) {
      _lastRefreshError = null;
      return null;
    }

    Uri uri;
    try {
      uri = Uri.parse(_cloudGatewayBaseUrl).resolve('/v1/subscription');
    } catch (_) {
      _lastRefreshError = null;
      return null;
    }

    try {
      final response = await _httpClient.get(
        uri,
        headers: <String, String>{
          'authorization': 'Bearer $idToken',
          'accept': 'application/json',
        },
      );
      if (response.statusCode != 200) {
        final body = response.body.trim();
        throw StateError(
          body.isEmpty
              ? 'cloud-gateway request failed: HTTP ${response.statusCode}'
              : 'cloud-gateway request failed: HTTP ${response.statusCode} $body',
        );
      }

      final decoded = response.tryDecodeObject();
      if (decoded == null) {
        throw const FormatException('invalid_subscription_response');
      }
      final active = decoded['active'];
      if (active is! bool) {
        throw const FormatException('invalid_subscription_response');
      }

      final rawCanManage = decoded['can_manage_subscription'];
      final canManageSubscription = rawCanManage is bool ? rawCanManage : null;
      _lastRefreshError = null;
      return _CloudSubscriptionSnapshot(
        status: active
            ? SubscriptionStatus.entitled
            : SubscriptionStatus.notEntitled,
        canManageSubscription: canManageSubscription,
      );
    } catch (error) {
      _lastRefreshError = error;
      return null;
    }
  }

  void _setState({
    required SubscriptionStatus status,
    required bool? canManageSubscription,
  }) {
    final statusChanged = _status != status;
    final canManageChanged = _canManageSubscription != canManageSubscription;
    if (!statusChanged && !canManageChanged) return;

    _status = status;
    _canManageSubscription = canManageSubscription;
    notifyListeners();
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}
