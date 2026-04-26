part of 'sync_config_store.dart';

String? _normalizeSyncConfigScopeKey(String? scopeKey) {
  final normalized = scopeKey?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}
