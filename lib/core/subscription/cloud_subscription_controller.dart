import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ai/ai_routing.dart';
import 'subscription_scope.dart';

final class CloudSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
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

  Future<void> refresh() async {
    final next = await _refreshFromCloudGateway();
    _setStatus(next ?? SubscriptionStatus.unknown);
  }

  Future<SubscriptionStatus?> _refreshFromCloudGateway() async {
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

      return active
          ? SubscriptionStatus.entitled
          : SubscriptionStatus.notEntitled;
    } catch (_) {
      return null;
    }
  }

  void _setStatus(SubscriptionStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _httpClient.close(force: true);
    super.dispose();
  }
}
