import 'sync_engine.dart';

enum SyncBackgroundDirection {
  pull,
  push,
}

enum SyncBackgroundResultStatus {
  success,
  skipped,
  failure,
}

final class SyncBackgroundResult {
  const SyncBackgroundResult({
    required this.backendType,
    required this.direction,
    required this.status,
    required this.timestampMs,
    this.statusCode,
    this.errorCode,
    this.errorMessage,
    this.userMessage,
    this.retryCount,
    this.durationMs,
  });

  final SyncBackendType backendType;
  final SyncBackgroundDirection direction;
  final SyncBackgroundResultStatus status;
  final int timestampMs;
  final int? statusCode;
  final String? errorCode;
  final String? errorMessage;
  final String? userMessage;
  final int? retryCount;
  final int? durationMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backendType': _backendTypeToWire(backendType),
      'direction': _directionToWire(direction),
      'status': _statusToWire(status),
      'timestampMs': timestampMs,
      'statusCode': statusCode,
      'errorCode': errorCode,
      'errorMessage': errorMessage,
      'userMessage': userMessage,
      'retryCount': retryCount,
      'durationMs': durationMs,
    };
  }

  static SyncBackgroundResult? fromJson(Map<String, dynamic> json) {
    final backendType = _backendTypeFromWire(json['backendType']);
    final direction = _directionFromWire(json['direction']);
    final status = _statusFromWire(json['status']);
    final timestampRaw = json['timestampMs'];
    final timestampMs = timestampRaw is int ? timestampRaw : null;
    if (backendType == null ||
        direction == null ||
        status == null ||
        timestampMs == null) {
      return null;
    }
    return SyncBackgroundResult(
      backendType: backendType,
      direction: direction,
      status: status,
      timestampMs: timestampMs,
      statusCode: _asInt(json['statusCode']),
      errorCode: _asString(json['errorCode']),
      errorMessage: _asString(json['errorMessage']),
      userMessage: _asString(json['userMessage']),
      retryCount: _asInt(json['retryCount']),
      durationMs: _asInt(json['durationMs']),
    );
  }
}

final class SyncBackgroundBackoffState {
  const SyncBackgroundBackoffState({
    required this.backendType,
    required this.retryCount,
    required this.nextAllowedAtMs,
    required this.updatedAtMs,
    this.lastStatusCode,
    this.lastErrorCode,
  });

  final SyncBackendType backendType;
  final int retryCount;
  final int nextAllowedAtMs;
  final int updatedAtMs;
  final int? lastStatusCode;
  final String? lastErrorCode;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backendType': _backendTypeToWire(backendType),
      'retryCount': retryCount,
      'nextAllowedAtMs': nextAllowedAtMs,
      'updatedAtMs': updatedAtMs,
      'lastStatusCode': lastStatusCode,
      'lastErrorCode': lastErrorCode,
    };
  }

  static SyncBackgroundBackoffState? fromJson(Map<String, dynamic> json) {
    final backendType = _backendTypeFromWire(json['backendType']);
    final retryCount = _asInt(json['retryCount']);
    final nextAllowedAtMs = _asInt(json['nextAllowedAtMs']);
    final updatedAtMs = _asInt(json['updatedAtMs']);
    if (backendType == null ||
        retryCount == null ||
        nextAllowedAtMs == null ||
        updatedAtMs == null) {
      return null;
    }
    return SyncBackgroundBackoffState(
      backendType: backendType,
      retryCount: retryCount,
      nextAllowedAtMs: nextAllowedAtMs,
      updatedAtMs: updatedAtMs,
      lastStatusCode: _asInt(json['lastStatusCode']),
      lastErrorCode: _asString(json['lastErrorCode']),
    );
  }
}

String _backendTypeToWire(SyncBackendType type) {
  return switch (type) {
    SyncBackendType.webdav => 'webdav',
    SyncBackendType.localDir => 'localdir',
    SyncBackendType.managedVault => 'managedvault',
  };
}

SyncBackendType? _backendTypeFromWire(Object? value) {
  final wire = _asString(value);
  return switch (wire) {
    'webdav' => SyncBackendType.webdav,
    'localdir' => SyncBackendType.localDir,
    'managedvault' => SyncBackendType.managedVault,
    _ => null,
  };
}

String _directionToWire(SyncBackgroundDirection direction) {
  return switch (direction) {
    SyncBackgroundDirection.pull => 'pull',
    SyncBackgroundDirection.push => 'push',
  };
}

SyncBackgroundDirection? _directionFromWire(Object? value) {
  final wire = _asString(value);
  return switch (wire) {
    'pull' => SyncBackgroundDirection.pull,
    'push' => SyncBackgroundDirection.push,
    _ => null,
  };
}

String _statusToWire(SyncBackgroundResultStatus status) {
  return switch (status) {
    SyncBackgroundResultStatus.success => 'success',
    SyncBackgroundResultStatus.skipped => 'skipped',
    SyncBackgroundResultStatus.failure => 'failure',
  };
}

SyncBackgroundResultStatus? _statusFromWire(Object? value) {
  final wire = _asString(value);
  return switch (wire) {
    'success' => SyncBackgroundResultStatus.success,
    'skipped' => SyncBackgroundResultStatus.skipped,
    'failure' => SyncBackgroundResultStatus.failure,
    _ => null,
  };
}

String? _asString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
