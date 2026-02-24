import 'dart:convert';

import '../../core/sync/sync_engine.dart';

final class OplogMaintenanceScopeInput {
  const OplogMaintenanceScopeInput({
    required this.backendType,
    required this.baseUrl,
    required this.localDir,
    required this.remoteRoot,
  });

  factory OplogMaintenanceScopeInput.fromSyncConfig(SyncConfig config) {
    return OplogMaintenanceScopeInput(
      backendType: config.backendType,
      baseUrl: config.baseUrl,
      localDir: config.localDir,
      remoteRoot: config.remoteRoot,
    );
  }

  final SyncBackendType backendType;
  final String? baseUrl;
  final String? localDir;
  final String remoteRoot;
}

String computeOplogMaintenanceScopeId(OplogMaintenanceScopeInput input) {
  switch (input.backendType) {
    case SyncBackendType.managedVault:
      final baseUrl = _requiredTrimmed(input.baseUrl, 'managedVault.baseUrl');
      final vaultId = input.remoteRoot.trim();
      if (vaultId.isEmpty) {
        throw StateError('managedVault.remoteRoot is empty');
      }
      final raw = 'managed_vault|$baseUrl|$vaultId';
      return _base64UrlNoPad(raw);
    case SyncBackendType.webdav:
      final baseUrl = _requiredTrimmed(input.baseUrl, 'webdav.baseUrl');
      final targetId = _webDavTargetId(baseUrl);
      final normalizedRoot = _normalizeRemoteRootDir(input.remoteRoot);
      return _base64UrlNoPad('$targetId|$normalizedRoot');
    case SyncBackendType.localDir:
      final localDir = _requiredTrimmed(input.localDir, 'localDir.path');
      final targetId = 'localdir:$localDir';
      final normalizedRoot = _normalizeRemoteRootDir(input.remoteRoot);
      return _base64UrlNoPad('$targetId|$normalizedRoot');
  }
}

String _requiredTrimmed(String? value, String fieldName) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    throw StateError('$fieldName is empty');
  }
  return trimmed;
}

String _normalizeRemoteRootDir(String remoteRoot) {
  final trimmed = remoteRoot.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  if (trimmed.isEmpty) {
    return '/';
  }
  return '/$trimmed/';
}

String _base64UrlNoPad(String value) {
  return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}

String _webDavTargetId(String baseUrl) {
  final parsed = Uri.parse(baseUrl);
  var basePath = parsed.path;
  if (!basePath.endsWith('/')) {
    basePath = '$basePath/';
  }

  final sanitized = Uri(
    scheme: parsed.scheme,
    userInfo: '',
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : null,
    path: basePath,
  );
  return 'webdav:$sanitized';
}
