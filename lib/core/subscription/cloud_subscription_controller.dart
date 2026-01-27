import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ai/ai_routing.dart';
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
    HttpClient? httpClient,
  })  : _idTokenGetter = idTokenGetter,
        _cloudGatewayBaseUrl = cloudGatewayBaseUrl,
        _httpClient = httpClient ?? HttpClient();

  final Future<String?> Function() _idTokenGetter;
  final String _cloudGatewayBaseUrl;
  final HttpClient _httpClient;

  SubscriptionStatus _status = SubscriptionStatus.unknown;
  @override
  SubscriptionStatus get status => _status;

  bool? _canManageSubscription;

  @override
  bool? get canManageSubscription => _canManageSubscription;

  Future<void> refresh() async {
    final next = await _refreshFromCloudGateway();
    _setState(
      status: next?.status ?? SubscriptionStatus.unknown,
      canManageSubscription: next?.canManageSubscription,
    );
  }

  Future<_CloudSubscriptionSnapshot?> _refreshFromCloudGateway() async {
    if (kIsWeb) return null;
    if (_cloudGatewayBaseUrl.trim().isEmpty) return null;

    String? idToken;
    try {
      idToken = await _idTokenGetter();
    } catch (_) {
      return null;
    }
    if (idToken == null || idToken.trim().isEmpty) return null;

    Uri uri;
    try {
      uri = Uri.parse(_cloudGatewayBaseUrl).resolve('/v1/subscription');
    } catch (_) {
      return null;
    }

    try {
      final req = await _httpClient.getUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      final active = decoded['active'];
      if (active is! bool) return null;

      final rawCanManage = decoded['can_manage_subscription'];
      final canManageSubscription = rawCanManage is bool ? rawCanManage : null;

      return _CloudSubscriptionSnapshot(
        status: active
            ? SubscriptionStatus.entitled
            : SubscriptionStatus.notEntitled,
        canManageSubscription: canManageSubscription,
      );
    } catch (_) {
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
    _httpClient.close(force: true);
    super.dispose();
  }
}
