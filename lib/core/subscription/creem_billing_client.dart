import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../cloud/http_json_client.dart';

typedef UrlOpener = Future<bool> Function(Uri url);

abstract interface class BillingClient {
  Future<void> openCheckout();

  Future<void> openPortal();
}

abstract interface class DisposableBillingClient implements BillingClient {
  void dispose();
}

final class CreemBillingClient implements DisposableBillingClient {
  CreemBillingClient({
    required Future<String?> Function() idTokenGetter,
    required String cloudGatewayBaseUrl,
    UrlOpener? urlOpener,
    http.Client? httpClient,
  })  : _idTokenGetter = idTokenGetter,
        _cloudGatewayBaseUrl = cloudGatewayBaseUrl,
        _urlOpener = urlOpener ?? _defaultUrlOpener,
        _httpClient = HttpJsonClient(client: httpClient);

  final Future<String?> Function() _idTokenGetter;
  final String _cloudGatewayBaseUrl;
  final UrlOpener _urlOpener;
  final HttpJsonClient _httpClient;

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

  @override
  void dispose() {
    _httpClient.close();
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
    final response = await _httpClient.postJson(
      endpoint,
      headers: <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: const <String, Object?>{},
    );

    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode} ${response.body}');
    }

    final decoded = response.tryDecodeObject();
    if (decoded == null) throw StateError('invalid_response');

    final rawUrl = decoded[urlField];
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      throw StateError('invalid_response');
    }

    return Uri.parse(rawUrl);
  }
}
