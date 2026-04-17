int? extractSyncHttpStatusCode(Object error) {
  final message = error.toString();
  final statusText =
      RegExp(r'\bHTTP\s+(\d{3})\b').firstMatch(message)?.group(1);
  if (statusText == null) return null;
  return int.tryParse(statusText);
}

String? extractSyncErrorCode(Object error) {
  final message = error.toString();
  return RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(message)?.group(1);
}

bool managedVaultPushFailureAllowsPull(Object error) {
  final statusCode = extractSyncHttpStatusCode(error);
  final errorCode = extractSyncErrorCode(error);
  return statusCode == 403 &&
      (errorCode == 'grace_readonly' || errorCode == 'storage_quota_exceeded');
}
