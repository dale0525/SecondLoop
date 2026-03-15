import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/cloud/cloud_usage_client.dart';
import '../core/cloud/vault_attachments_client.dart';
import '../core/cloud/vault_usage_client.dart';
import '../core/subscription/cloud_subscription_controller.dart';
import '../core/subscription/creem_billing_client.dart';
import '../core/cloud/cloud_auth_controller.dart';
import 'web_app_service.dart';

const String kWebFormalSettingsBaseUrl = 'https://web.secondloop.invalid/';

final class WebAppBillingClient implements BillingClient {
  WebAppBillingClient({
    required this.service,
    required this.authController,
  });

  final WebAppService service;
  final CloudAuthController authController;

  @override
  Future<void> openCheckout() async {
    final idToken = await authController.getIdToken();
    if (idToken == null || idToken.trim().isEmpty) {
      throw StateError('missing_id_token');
    }
    await service.openCheckout(idToken: idToken);
  }

  @override
  Future<void> openPortal() async {
    final idToken = await authController.getIdToken();
    if (idToken == null || idToken.trim().isEmpty) {
      throw StateError('missing_id_token');
    }
    await service.openPortal(idToken: idToken);
  }
}

final class WebFormalSettingsHttpClient extends http.BaseClient {
  WebFormalSettingsHttpClient({
    required this.service,
    required this.authController,
  });

  final WebAppService service;
  final CloudAuthController authController;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final idToken = await authController.getIdToken();
    if (idToken == null || idToken.trim().isEmpty) {
      return _jsonResponse(
        request,
        statusCode: 401,
        body: <String, Object?>{'error': 'missing_id_token'},
      );
    }

    final segments = request.url.pathSegments;
    if (request.method == 'GET' && request.url.path == '/v1/subscription') {
      final subscription = await service.fetchSubscription(idToken: idToken);
      final isEntitled = subscription == WebSubscriptionState.entitled;
      return _jsonResponse(
        request,
        body: <String, Object?>{
          'active': isEntitled,
          'can_manage_subscription': isEntitled,
        },
      );
    }

    if (request.method == 'POST' &&
        request.url.path == '/v1/billing/checkout') {
      return _jsonResponse(
        request,
        body: const <String, Object?>{
          'checkout_url': 'https://checkout.secondloop.test/session',
        },
      );
    }

    if (request.method == 'POST' && request.url.path == '/v1/billing/portal') {
      return _jsonResponse(
        request,
        body: const <String, Object?>{
          'portal_url': 'https://billing.secondloop.test/portal',
        },
      );
    }

    if (request.method == 'GET' && request.url.path == '/v1/usage') {
      final summary = await service.fetchUsage(idToken: idToken);
      return _jsonResponse(
        request,
        body: <String, Object?>{
          'ask_ai_usage_percent': summary?.askAiUsagePercent ?? 0,
          'embeddings_usage_percent': summary?.embeddingsUsagePercent ?? 0,
          'reset_at_ms': summary?.resetAtMs,
        },
      );
    }

    if (segments.length >= 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'vaults') {
      final vaultId = segments[2];
      if (request.method == 'GET' &&
          segments.length == 4 &&
          segments[3] == 'usage') {
        final summary = await service.fetchVaultUsage(
          idToken: idToken,
          vaultId: vaultId,
        );
        return _jsonResponse(
          request,
          body: <String, Object?>{
            'total_bytes_used': summary?.totalBytesUsed ?? 0,
            'attachments_bytes_used': summary?.totalBytesUsed ?? 0,
            'ops_bytes_used': 0,
            'other_bytes_used': 0,
            'limit_bytes': summary?.limitBytes,
          },
        );
      }

      if (request.method == 'GET' &&
          segments.length == 4 &&
          segments[3] == 'attachments') {
        final items = await service.listVaultAttachments(
          idToken: idToken,
          vaultId: vaultId,
        );
        final totalBytes =
            items.fold<int>(0, (sum, item) => sum + item.byteLen);
        return _jsonResponse(
          request,
          body: <String, Object?>{
            'items': items
                .map(
                  (item) => <String, Object?>{
                    'sha256': item.sha256,
                    'root_sha256': item.rootSha256,
                    'group_type': item.groupType,
                    'leaf_count': item.leafCount,
                    'mime_type': item.mimeType,
                    'byte_len': item.byteLen,
                    'created_at_ms': item.createdAtMs,
                    'uploaded_at_ms': item.uploadedAtMs,
                  },
                )
                .toList(growable: false),
            'total_count': items.length,
            'total_bytes_used': totalBytes,
          },
        );
      }

      if (request.method == 'DELETE' &&
          segments.length == 5 &&
          segments[3] == 'attachments') {
        final sha256 = segments[4];
        await service.deleteVaultAttachment(
          idToken: idToken,
          vaultId: vaultId,
          sha256: sha256,
        );
        return _jsonResponse(
          request,
          body: <String, Object?>{
            'deleted': true,
            'sha256': sha256,
          },
        );
      }
    }

    return _jsonResponse(
      request,
      statusCode: 404,
      body: <String, Object?>{'error': 'unsupported_bridge_request'},
    );
  }

  http.StreamedResponse _jsonResponse(
    http.BaseRequest request, {
    int statusCode = 200,
    required Map<String, Object?> body,
  }) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      request: request,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }

  @override
  void close() {}
}

CloudUsageClient createWebFormalCloudUsageClient({
  required WebAppService service,
  required CloudAuthController authController,
}) {
  return CloudUsageClient(
    httpClient: WebFormalSettingsHttpClient(
      service: service,
      authController: authController,
    ),
  );
}

VaultUsageClient createWebFormalVaultUsageClient({
  required WebAppService service,
  required CloudAuthController authController,
}) {
  return VaultUsageClient(
    httpClient: WebFormalSettingsHttpClient(
      service: service,
      authController: authController,
    ),
  );
}

VaultAttachmentsClient createWebFormalVaultAttachmentsClient({
  required WebAppService service,
  required CloudAuthController authController,
}) {
  return VaultAttachmentsClient(
    httpClient: WebFormalSettingsHttpClient(
      service: service,
      authController: authController,
    ),
  );
}

CloudSubscriptionController createWebFormalSubscriptionController({
  required WebAppService service,
  required CloudAuthController authController,
}) {
  return CloudSubscriptionController(
    idTokenGetter: authController.getIdToken,
    cloudGatewayBaseUrl: kWebFormalSettingsBaseUrl,
    httpClient: WebFormalSettingsHttpClient(
      service: service,
      authController: authController,
    ),
  );
}
