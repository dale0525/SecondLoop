import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_json_client.dart';

@immutable
class VaultAttachmentUsageItem {
  const VaultAttachmentUsageItem({
    required this.sha256,
    required this.mimeType,
    required this.byteLen,
    required this.createdAtMs,
    required this.uploadedAtMs,
    this.id,
    this.displayName,
    this.linkedEntities = const <VaultAttachmentLinkedEntity>[],
    this.preview,
    this.processingStatus,
    this.canDelete = true,
    this.rootSha256,
    this.groupType,
    this.leafCount,
  });

  final String? id;
  final String sha256;
  final String? displayName;
  final String mimeType;
  final int byteLen;
  final int? createdAtMs;
  final int? uploadedAtMs;
  final List<VaultAttachmentLinkedEntity> linkedEntities;
  final VaultAttachmentPreview? preview;
  final String? processingStatus;
  final bool canDelete;
  final String? rootSha256;
  final String? groupType;
  final int? leafCount;

  String get attachmentId {
    final normalizedId = id?.trim() ?? '';
    if (normalizedId.isNotEmpty) return normalizedId;
    return primarySha256;
  }

  String get primarySha256 {
    final normalizedRoot = rootSha256?.trim() ?? '';
    if (normalizedRoot.isNotEmpty) return normalizedRoot;
    return sha256;
  }

  bool get isGroupedVideo => groupType?.trim() == 'video';
}

@immutable
class VaultAttachmentPreview {
  const VaultAttachmentPreview({
    required this.kind,
    required this.url,
    this.thumbnailUrl,
  });

  final String kind;
  final String url;
  final String? thumbnailUrl;
}

@immutable
class VaultAttachmentContent {
  const VaultAttachmentContent({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

@immutable
class VaultAttachmentLinkedEntity {
  const VaultAttachmentLinkedEntity({
    required this.kind,
    required this.id,
    this.title,
  });

  final String kind;
  final String id;
  final String? title;
}

@immutable
class VaultAttachmentDeleteImpact {
  const VaultAttachmentDeleteImpact({
    required this.requiresConfirmation,
    required this.linkedEntities,
  });

  final bool requiresConfirmation;
  final List<VaultAttachmentLinkedEntity> linkedEntities;
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
  VaultAttachmentsClient({http.Client? httpClient})
      : _httpClient = HttpJsonClient(client: httpClient);

  final HttpJsonClient _httpClient;

  Future<VaultAttachmentUsageList> fetchVaultAttachmentUsageList({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    int limit = 200,
  }) async {
    final uri = _resolveVaultUri(
      managedVaultBaseUrl,
      '/v1/vaults/$vaultId/attachments?limit=$limit',
    );
    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = response.tryDecodeObject();
    if (decoded == null) {
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
      final id = '${map['id'] ?? ''}'.trim();
      final displayName = _firstString(
        map['display_name'],
        map['displayName'],
        map['filename'],
        map['file_name'],
        map['name'],
      );
      final processingStatus = '${map['processing_status'] ?? ''}'.trim();
      final linkedEntities = _parseLinkedEntities(map['linked_entities']);
      final preview = _parsePreview(map['preview']);
      final canDelete = _parseBool(map['can_delete']) ?? true;

      if (sha256.isEmpty || byteLen == null) {
        throw const FormatException('invalid_vault_attachment_item_fields');
      }

      items.add(
        VaultAttachmentUsageItem(
          id: id.isEmpty ? null : id,
          sha256: sha256,
          displayName: displayName.isEmpty ? null : displayName,
          mimeType: mimeType,
          byteLen: byteLen,
          createdAtMs: createdAtMs,
          uploadedAtMs: uploadedAtMs,
          linkedEntities: linkedEntities,
          preview: preview,
          processingStatus: processingStatus.isEmpty ? null : processingStatus,
          canDelete: canDelete,
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

  Future<VaultAttachmentPreview> fetchAttachmentPreview({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required String attachmentId,
  }) async {
    final directUri = _resolveVaultUri(
      managedVaultBaseUrl,
      '/v1/vaults/$vaultId/attachments/$attachmentId',
    );
    final uri = _resolveVaultUri(
      managedVaultBaseUrl,
      '/v1/vaults/$vaultId/attachments/$attachmentId/preview',
    );
    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404) {
        return VaultAttachmentPreview(
          kind: 'download',
          url: directUri.toString(),
        );
      }
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = response.tryDecodeObject();
    final preview = _parsePreview(decoded, baseUri: uri);
    if (preview == null) {
      throw const FormatException('invalid_vault_attachment_preview');
    }
    return preview;
  }

  Future<VaultAttachmentContent> fetchAttachmentContent({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required String attachmentId,
    String? contentUrl,
  }) async {
    final candidates = <Uri>[];
    void addCandidate(Uri uri) {
      if (candidates
          .any((candidate) => candidate.toString() == uri.toString())) {
        return;
      }
      candidates.add(uri);
    }

    final normalizedContentUrl = contentUrl?.trim() ?? '';
    if (normalizedContentUrl.isNotEmpty) {
      addCandidate(_resolveVaultUri(managedVaultBaseUrl, normalizedContentUrl));
    }
    addCandidate(
      _resolveVaultUri(
        managedVaultBaseUrl,
        '/v1/vaults/$vaultId/attachments/$attachmentId/content',
      ),
    );
    addCandidate(
      _resolveVaultUri(
        managedVaultBaseUrl,
        '/v1/vaults/$vaultId/attachments/$attachmentId',
      ),
    );

    Object? lastError;
    for (final uri in candidates) {
      final response = await _httpClient.getRaw(
        uri,
        headers: <String, String>{
          'authorization': 'Bearer $idToken',
          'accept': '*/*',
        },
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final mimeType = response.headers['content-type']?.trim();
        return VaultAttachmentContent(
          bytes: Uint8List.fromList(response.bodyBytes),
          mimeType: mimeType == null || mimeType.isEmpty
              ? 'application/octet-stream'
              : mimeType,
        );
      }
      lastError = Exception('HTTP ${response.statusCode}: ${response.body}');
      if (response.statusCode != 404 && response.statusCode != 405) {
        throw lastError;
      }
    }

    throw lastError ??
        const FormatException('invalid_vault_attachment_content');
  }

  Future<VaultAttachmentDeleteImpact> fetchDeleteImpact({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required String attachmentId,
  }) async {
    final uri = _resolveVaultUri(
      managedVaultBaseUrl,
      '/v1/vaults/$vaultId/attachments/$attachmentId/delete-impact',
    );
    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = response.tryDecodeObject();
    if (decoded == null) {
      throw const FormatException('invalid_vault_attachment_delete_impact');
    }

    return VaultAttachmentDeleteImpact(
      requiresConfirmation:
          _parseBool(decoded['requires_confirmation']) ?? false,
      linkedEntities: _parseLinkedEntities(decoded['linked_entities']),
    );
  }

  Future<void> deleteVaultAttachment({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    String? attachmentId,
    String? attachmentSha256,
  }) async {
    final target = (attachmentId?.trim().isNotEmpty ?? false)
        ? attachmentId!.trim()
        : attachmentSha256?.trim() ?? '';
    if (target.isEmpty) {
      throw ArgumentError.value(target, 'attachmentId', 'must not be empty');
    }
    final uri = _resolveVaultUri(
      managedVaultBaseUrl,
      '/v1/vaults/$vaultId/attachments/$target',
    );
    final response = await _httpClient.delete(
      uri,
      headers: <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

Uri _resolveVaultUri(String baseUrl, String path) {
  try {
    return Uri.parse(baseUrl).resolve(path);
  } catch (_) {
    throw FormatException('invalid_managed_vault_base_url', baseUrl);
  }
}

int? _parseInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value);
  return null;
}

bool? _parseBool(Object? value) {
  if (value is bool) return value;
  if (value is String) return bool.tryParse(value);
  return null;
}

String _firstString(Object? first, Object? second, Object? third,
    Object? fourth, Object? fifth) {
  for (final value in <Object?>[first, second, third, fourth, fifth]) {
    final text = '${value ?? ''}'.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

String _resolvePreviewUrl(String value, Uri? baseUri) {
  final parsed = Uri.tryParse(value);
  if (parsed == null || baseUri == null || parsed.hasScheme) return value;
  return baseUri.resolveUri(parsed).toString();
}

VaultAttachmentPreview? _parsePreview(Object? value, {Uri? baseUri}) {
  if (value is! Map) return null;
  final map = Map<String, Object?>.from(value);
  final kind = '${map['kind'] ?? ''}'.trim();
  final url = '${map['url'] ?? ''}'.trim();
  final thumbnailUrl = '${map['thumbnail_url'] ?? ''}'.trim();
  if (kind.isEmpty || url.isEmpty) return null;
  return VaultAttachmentPreview(
    kind: kind,
    url: _resolvePreviewUrl(url, baseUri),
    thumbnailUrl:
        thumbnailUrl.isEmpty ? null : _resolvePreviewUrl(thumbnailUrl, baseUri),
  );
}

List<VaultAttachmentLinkedEntity> _parseLinkedEntities(Object? value) {
  if (value is! List) return const <VaultAttachmentLinkedEntity>[];
  final entities = <VaultAttachmentLinkedEntity>[];
  for (final raw in value) {
    if (raw is! Map) continue;
    final map = Map<String, Object?>.from(raw);
    final kind = '${map['kind'] ?? ''}'.trim();
    final id = '${map['id'] ?? ''}'.trim();
    final title = '${map['title'] ?? ''}'.trim();
    if (kind.isEmpty || id.isEmpty) continue;
    entities.add(
      VaultAttachmentLinkedEntity(
        kind: kind,
        id: id,
        title: title.isEmpty ? null : title,
      ),
    );
  }
  return List<VaultAttachmentLinkedEntity>.unmodifiable(entities);
}
