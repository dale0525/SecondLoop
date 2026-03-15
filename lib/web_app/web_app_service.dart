import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../features/attachments/web_media_processing_notice.dart';

const String _kApiCloudConfigPath = '/api/cloud/config';
const String _kApiSubscriptionPath = '/api/app/subscription';
const String _kApiBillingCheckoutPath = '/api/app/billing/checkout';
const String _kApiBillingPortalPath = '/api/app/billing/portal';
const String _kApiUsagePath = '/api/app/usage';
const String _kApiChatPath = '/api/app/chat';
const String _kApiVaultUsagePath = '/api/app/vault/usage';
const String _kApiVaultAttachmentsPath = '/api/app/vault/attachments';
const String _kApiVaultAttachmentPath = '/api/app/vault/attachment';

enum WebSubscriptionState {
  unknown,
  entitled,
  notEntitled,
}

class WebSubscriptionSnapshot {
  const WebSubscriptionSnapshot({
    required this.state,
    required this.canManageSubscription,
  });

  final WebSubscriptionState state;
  final bool? canManageSubscription;
}

class WebUsageSummary {
  const WebUsageSummary({
    required this.askAiUsagePercent,
    required this.embeddingsUsagePercent,
    required this.resetAtMs,
  });

  final int askAiUsagePercent;
  final int embeddingsUsagePercent;
  final int? resetAtMs;
}

class WebVaultUsageSummary {
  const WebVaultUsageSummary({
    required this.totalBytesUsed,
    required this.limitBytes,
  });

  final int totalBytesUsed;
  final int? limitBytes;
}

class WebVaultAttachmentItem {
  const WebVaultAttachmentItem({
    required this.sha256,
    required this.mimeType,
    required this.byteLen,
    this.createdAtMs,
    this.uploadedAtMs,
    this.rootSha256,
    this.groupType,
    this.leafCount,
  });

  final String sha256;
  final String mimeType;
  final int byteLen;
  final int? createdAtMs;
  final int? uploadedAtMs;
  final String? rootSha256;
  final String? groupType;
  final int? leafCount;

  String get primarySha256 {
    final normalizedRoot = rootSha256?.trim() ?? '';
    if (normalizedRoot.isNotEmpty) return normalizedRoot;
    return sha256;
  }

  bool get needsAppProcessing => needsAppProcessingInWeb(mimeType);
}

abstract class WebAppService {
  Future<WebSubscriptionSnapshot> fetchSubscription({required String idToken});

  Future<void> openCheckout({required String idToken}) async {}

  Future<void> openPortal({required String idToken}) async {}

  Future<WebUsageSummary?> fetchUsage({required String idToken}) async => null;

  Future<String> sendChat({
    required String idToken,
    required List<Map<String, String>> messages,
  }) async =>
      '';

  Future<WebVaultUsageSummary?> fetchVaultUsage({
    required String idToken,
    required String vaultId,
  }) async =>
      null;

  Future<List<WebVaultAttachmentItem>> listVaultAttachments({
    required String idToken,
    required String vaultId,
  }) async =>
      const <WebVaultAttachmentItem>[];

  Future<void> uploadVaultAttachment({
    required String idToken,
    required String vaultId,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
  }) async {}

  Future<void> deleteVaultAttachment({
    required String idToken,
    required String vaultId,
    required String sha256,
  }) async {}

  Future<List<int>> fetchVaultAttachmentBytes({
    required String idToken,
    required String vaultId,
    required String sha256,
  }) async =>
      const <int>[];

  Future<Uri> buildAttachmentDownloadUri({required String sha256}) async =>
      Uri(path: _kApiVaultAttachmentPath, queryParameters: {'sha256': sha256});
}

class WebAppConfig {
  const WebAppConfig({required this.firebaseWebApiKey});

  final String firebaseWebApiKey;
}

class WebAppHttpException implements Exception {
  const WebAppHttpException({
    required this.statusCode,
    required this.body,
    this.code,
  });

  final int statusCode;
  final String body;
  final String? code;

  @override
  String toString() {
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) {
      return 'HTTP $statusCode';
    }
    return 'HTTP $statusCode: $normalizedBody';
  }
}

class WebAppServiceHttp extends WebAppService {
  WebAppServiceHttp({
    http.Client? client,
    Future<bool> Function(Uri url)? urlOpener,
  })  : _client = client ?? http.Client(),
        _urlOpener = urlOpener ?? _defaultUrlOpener;

  final http.Client _client;
  final Future<bool> Function(Uri url) _urlOpener;

  static Future<bool> _defaultUrlOpener(Uri url) {
    return launchUrl(url, mode: LaunchMode.platformDefault);
  }

  static Future<WebAppConfig> loadConfig({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(Uri(path: _kApiCloudConfigPath));
      if (response.statusCode != 200) {
        throw StateError('config_http_${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('invalid_config_response');
      }
      final firebaseWebApiKey =
          '${decoded['firebase_web_api_key'] ?? ''}'.trim();
      return WebAppConfig(firebaseWebApiKey: firebaseWebApiKey);
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    String idToken, {
    Map<String, String>? headers,
  }) async {
    final response = await _client.get(
      Uri(path: path),
      headers: <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
        ...?headers,
      },
    );
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> _sendJson(
    String path,
    String idToken, {
    String method = 'POST',
    Object? body,
    Map<String, String>? headers,
  }) async {
    final request = http.Request(method, Uri(path: path));
    request.headers.addAll(<String, String>{
      'authorization': 'Bearer $idToken',
      'accept': 'application/json',
      'content-type': 'application/json',
      ...?headers,
    });
    if (body != null) {
      request.body = jsonEncode(body);
    } else {
      request.body = '{}';
    }
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    return _decodeJsonResponse(response);
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    Map<String, dynamic> map = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body) as Object?;
        map = decoded is Map<String, dynamic>
            ? decoded
            : decoded is Map
                ? decoded.map((key, value) => MapEntry('$key', value))
                : <String, dynamic>{};
      } on FormatException {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw WebAppHttpException(
            statusCode: response.statusCode,
            body: response.body,
          );
        }
        throw const FormatException('invalid_json_response');
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebAppHttpException(
        statusCode: response.statusCode,
        body: map.isEmpty ? response.body : jsonEncode(map),
        code: map['error'] is String ? map['error'] as String : null,
      );
    }
    return map;
  }

  Map<String, String> _vaultHeaders(String vaultId) => <String, String>{
        'x-secondloop-vault-id': vaultId,
      };

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription(
      {required String idToken}) async {
    final json = await _getJson(_kApiSubscriptionPath, idToken);
    final active = json['active'];
    if (active is bool) {
      return WebSubscriptionSnapshot(
        state: active
            ? WebSubscriptionState.entitled
            : WebSubscriptionState.notEntitled,
        canManageSubscription: json['can_manage_subscription'] is bool
            ? json['can_manage_subscription'] as bool
            : null,
      );
    }
    return const WebSubscriptionSnapshot(
      state: WebSubscriptionState.unknown,
      canManageSubscription: null,
    );
  }

  @override
  Future<void> openCheckout({required String idToken}) async {
    final json = await _sendJson(_kApiBillingCheckoutPath, idToken);
    final rawUrl = '${json['checkout_url'] ?? ''}'.trim();
    if (rawUrl.isEmpty) throw StateError('missing_checkout_url');
    final ok = await _urlOpener(Uri.parse(rawUrl));
    if (!ok) throw StateError('open_url_failed');
  }

  @override
  Future<void> openPortal({required String idToken}) async {
    final json = await _sendJson(_kApiBillingPortalPath, idToken);
    final rawUrl = '${json['portal_url'] ?? ''}'.trim();
    if (rawUrl.isEmpty) throw StateError('missing_portal_url');
    final ok = await _urlOpener(Uri.parse(rawUrl));
    if (!ok) throw StateError('open_url_failed');
  }

  @override
  Future<WebUsageSummary?> fetchUsage({required String idToken}) async {
    final json = await _getJson(_kApiUsagePath, idToken);
    return WebUsageSummary(
      askAiUsagePercent: (json['ask_ai_usage_percent'] as num?)?.toInt() ?? 0,
      embeddingsUsagePercent:
          (json['embeddings_usage_percent'] as num?)?.toInt() ?? 0,
      resetAtMs: (json['reset_at_ms'] as num?)?.toInt(),
    );
  }

  @override
  Future<String> sendChat({
    required String idToken,
    required List<Map<String, String>> messages,
  }) async {
    final json = await _sendJson(
      _kApiChatPath,
      idToken,
      body: <String, Object?>{
        'messages': messages,
      },
    );
    return '${json['content'] ?? ''}'.trim();
  }

  @override
  Future<WebVaultUsageSummary?> fetchVaultUsage({
    required String idToken,
    required String vaultId,
  }) async {
    final json = await _getJson(
      _kApiVaultUsagePath,
      idToken,
      headers: _vaultHeaders(vaultId),
    );
    return WebVaultUsageSummary(
      totalBytesUsed: (json['total_bytes_used'] as num?)?.toInt() ?? 0,
      limitBytes: (json['limit_bytes'] as num?)?.toInt(),
    );
  }

  @override
  Future<List<WebVaultAttachmentItem>> listVaultAttachments({
    required String idToken,
    required String vaultId,
  }) async {
    final json = await _getJson(
      _kApiVaultAttachmentsPath,
      idToken,
      headers: _vaultHeaders(vaultId),
    );
    final rawItems = json['items'];
    if (rawItems is! List) return const <WebVaultAttachmentItem>[];
    return rawItems
        .whereType<Map>()
        .map((raw) => WebVaultAttachmentItem(
              sha256: '${raw['sha256'] ?? ''}',
              mimeType: '${raw['mime_type'] ?? ''}',
              byteLen: (raw['byte_len'] as num?)?.toInt() ?? 0,
              createdAtMs: (raw['created_at_ms'] as num?)?.toInt(),
              uploadedAtMs: (raw['uploaded_at_ms'] as num?)?.toInt(),
              rootSha256: '${raw['root_sha256'] ?? ''}'.trim().isEmpty
                  ? null
                  : '${raw['root_sha256']}',
              groupType: '${raw['group_type'] ?? ''}'.trim().isEmpty
                  ? null
                  : '${raw['group_type']}',
              leafCount: (raw['leaf_count'] as num?)?.toInt(),
            ))
        .where((item) => item.sha256.trim().isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> uploadVaultAttachment({
    required String idToken,
    required String vaultId,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final sha256 = await _sha256Hex(bytes);
    final request = http.Request(
      'PUT',
      Uri(path: _kApiVaultAttachmentPath, queryParameters: {'sha256': sha256}),
    );
    request.headers.addAll(<String, String>{
      'authorization': 'Bearer $idToken',
      'content-type': mimeType,
      'x-file-name': fileName,
      'x-file-size': '${bytes.length}',
      ..._vaultHeaders(vaultId),
    });
    request.bodyBytes = bytes;
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _decodeJsonResponse(response);
  }

  @override
  Future<List<int>> fetchVaultAttachmentBytes({
    required String idToken,
    required String vaultId,
    required String sha256,
  }) async {
    final request = http.Request(
      'GET',
      Uri(path: _kApiVaultAttachmentPath, queryParameters: {'sha256': sha256}),
    );
    request.headers.addAll(<String, String>{
      'authorization': 'Bearer $idToken',
      'accept': '*/*',
      ..._vaultHeaders(vaultId),
    });
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeJsonResponse(response);
    }
    return response.bodyBytes;
  }

  @override
  Future<void> deleteVaultAttachment({
    required String idToken,
    required String vaultId,
    required String sha256,
  }) async {
    final request = http.Request(
      'DELETE',
      Uri(path: _kApiVaultAttachmentPath, queryParameters: {'sha256': sha256}),
    );
    request.headers.addAll(<String, String>{
      'authorization': 'Bearer $idToken',
      'accept': 'application/json',
      ..._vaultHeaders(vaultId),
    });
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _decodeJsonResponse(response);
  }
}

Future<String> _sha256Hex(List<int> bytes) async {
  final digest = await Sha256().hash(bytes);
  return _hexEncodeBytes(digest.bytes);
}

String _hexEncodeBytes(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String guessMimeTypeFromExtension(String? extension) {
  switch ((extension ?? '').toLowerCase()) {
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'md':
      return 'text/markdown';
    case 'json':
      return 'application/json';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'm4a':
      return 'audio/mp4';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    default:
      return 'application/octet-stream';
  }
}
