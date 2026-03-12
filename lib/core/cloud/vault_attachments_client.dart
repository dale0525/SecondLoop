import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class VaultAttachmentUsageItem {
  const VaultAttachmentUsageItem({
    required this.sha256,
    required this.mimeType,
    required this.byteLen,
    required this.createdAtMs,
    required this.uploadedAtMs,
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

  bool get isGroupedVideo => groupType?.trim() == 'video';
}

@immutable
class VaultAttachmentUsageList {
  const VaultAttachmentUsageList({
    required this.items,
    required this.totalCount,
    required this.totalBytesUsed,
  });

  final List<VaultAttachmentUsageItem> items;
  final int totalCount;
  final int totalBytesUsed;
}

final class VaultAttachmentsClient {
  VaultAttachmentsClient({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<VaultAttachmentUsageList> fetchVaultAttachmentUsageList({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    int limit = 200,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Vault attachments usage is not supported on web');
    }

    Uri uri;
    try {
      uri = Uri.parse(managedVaultBaseUrl)
          .resolve('/v1/vaults/$vaultId/attachments?limit=$limit');
    } catch (_) {
      throw FormatException(
        'invalid_managed_vault_base_url',
        managedVaultBaseUrl,
      );
    }

    final req = await _httpClient.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final resp = await req.close();
    final text = await utf8.decodeStream(resp);

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: $text');
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid_vault_attachments_response');
    }

    final rawItems = decoded['items'];
    final totalCount = _parseInt(decoded['total_count']);
    final totalBytesUsed = _parseInt(decoded['total_bytes_used']);

    if (rawItems is! List || totalCount == null || totalBytesUsed == null) {
      throw const FormatException('invalid_vault_attachments_response_fields');
    }

    final items = <VaultAttachmentUsageItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) {
        throw const FormatException('invalid_vault_attachment_item');
      }
      final map = Map<String, Object?>.from(raw);
      final sha256 = '${map['sha256'] ?? ''}'.trim();
      final mimeType = '${map['mime_type'] ?? ''}'.trim();
      final byteLen = _parseInt(map['byte_len']);
      final createdAtMs = _parseInt(map['created_at_ms']);
      final uploadedAtMs = _parseInt(map['uploaded_at_ms']);
      final rootSha256 = '${map['root_sha256'] ?? ''}'.trim();
      final groupType = '${map['group_type'] ?? ''}'.trim();
      final leafCount = _parseInt(map['leaf_count']);

      if (sha256.isEmpty || byteLen == null) {
        throw const FormatException('invalid_vault_attachment_item_fields');
      }

      items.add(
        VaultAttachmentUsageItem(
          sha256: sha256,
          mimeType: mimeType,
          byteLen: byteLen,
          createdAtMs: createdAtMs,
          uploadedAtMs: uploadedAtMs,
          rootSha256: rootSha256.isEmpty ? null : rootSha256,
          groupType: groupType.isEmpty ? null : groupType,
          leafCount: leafCount,
        ),
      );
    }

    return VaultAttachmentUsageList(
      items: items,
      totalCount: totalCount,
      totalBytesUsed: totalBytesUsed,
    );
  }

  Future<void> deleteVaultAttachment({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required String attachmentSha256,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'Vault attachment deletion is not supported on web');
    }

    Uri uri;
    try {
      uri = Uri.parse(managedVaultBaseUrl)
          .resolve('/v1/vaults/$vaultId/attachments/$attachmentSha256');
    } catch (_) {
      throw FormatException(
        'invalid_managed_vault_base_url',
        managedVaultBaseUrl,
      );
    }

    final req = await _httpClient.deleteUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final resp = await req.close();
    final text = await utf8.decodeStream(resp);

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: $text');
    }
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}

int? _parseInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value);
  return null;
}
