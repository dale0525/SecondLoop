import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

typedef UrlOpener = Future<bool> Function(Uri url);

abstract interface class BillingClient {
  Future<void> openCheckout();

  Future<void> openPortal();
}

final class CreemBillingClient implements BillingClient {
  CreemBillingClient({
    required Future<String?> Function() idTokenGetter,
    required String cloudGatewayBaseUrl,
    UrlOpener? urlOpener,
    HttpClient Function()? httpClientFactory,
  })  : _idTokenGetter = idTokenGetter,
        _cloudGatewayBaseUrl = cloudGatewayBaseUrl,
        _urlOpener = urlOpener ?? _defaultUrlOpener,
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Future<String?> Function() _idTokenGetter;
  final String _cloudGatewayBaseUrl;
  final UrlOpener _urlOpener;
  final HttpClient Function() _httpClientFactory;

  static Future<bool> _defaultUrlOpener(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Future<void> openCheckout() async {
    final url = await _postAndExtractUrl(
      '/v1/billing/checkout',
      urlField: 'checkout_url',
    );
    await _openOrThrow(url);
  }

  @override
  Future<void> openPortal() async {
    final url = await _postAndExtractUrl(
      '/v1/billing/portal',
      urlField: 'portal_url',
    );
    await _openOrThrow(url);
  }

  Future<void> _openOrThrow(Uri url) async {
    final ok = await _urlOpener(url);
    if (!ok) throw StateError('open_url_failed');
  }

  Future<Uri> _postAndExtractUrl(
    String path, {
    required String urlField,
  }) async {
    final baseUrl = _cloudGatewayBaseUrl.trim();
    if (baseUrl.isEmpty) throw StateError('missing_cloud_gateway_base_url');

    final idToken = await _idTokenGetter();
    if (idToken == null || idToken.trim().isEmpty) {
      throw StateError('missing_id_token');
    }

    final endpoint = Uri.parse(baseUrl).resolve(path);
    final client = _httpClientFactory();
    try {
      final req = await client.postUrl(endpoint);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode('{}'));

      final resp = await req.close();
      final text = await utf8.decodeStream(resp);

      if (resp.statusCode != 200) {
        throw StateError('HTTP ${resp.statusCode} $text');
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map) throw StateError('invalid_response');

      final rawUrl = decoded[urlField];
      if (rawUrl is! String || rawUrl.trim().isEmpty) {
        throw StateError('invalid_response');
      }

      return Uri.parse(rawUrl);
    } finally {
      client.close(force: true);
    }
  }
}
