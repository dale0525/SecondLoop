import 'package:flutter/foundation.dart';

enum CloudRuntimeMode {
  selfManaged,
  managedPro,
}

enum CloudRuntimeAuthMode {
  runtimeToken,
  hostedSession,
}

@immutable
class CloudRuntimeProfile {
  const CloudRuntimeProfile({
    required this.runtimeMode,
    required this.apiBaseUrl,
    required this.authMode,
    required this.authToken,
    required this.capabilityManifestId,
    required this.manifestVersion,
  });

  final CloudRuntimeMode runtimeMode;
  final String apiBaseUrl;
  final CloudRuntimeAuthMode authMode;
  final String authToken;
  final String capabilityManifestId;
  final int manifestVersion;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'runtime_mode': runtimeMode.wireValue,
      'api_base_url': apiBaseUrl,
      'auth_mode': authMode.wireValue,
      'auth_token': authToken,
      'capability_manifest_id': capabilityManifestId,
      'manifest_version': manifestVersion,
    };
  }

  factory CloudRuntimeProfile.fromJson(Map<String, dynamic> json) {
    return CloudRuntimeProfile(
      runtimeMode: cloudRuntimeModeFromWire(json['runtime_mode']),
      apiBaseUrl: (json['api_base_url'] as String?) ?? '',
      authMode: cloudRuntimeAuthModeFromWire(json['auth_mode']),
      authToken: (json['auth_token'] as String?) ?? '',
      capabilityManifestId: (json['capability_manifest_id'] as String?) ?? '',
      manifestVersion: (json['manifest_version'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CloudRuntimeProfile &&
        other.runtimeMode == runtimeMode &&
        other.apiBaseUrl == apiBaseUrl &&
        other.authMode == authMode &&
        other.authToken == authToken &&
        other.capabilityManifestId == capabilityManifestId &&
        other.manifestVersion == manifestVersion;
  }

  @override
  int get hashCode => Object.hash(
        runtimeMode,
        apiBaseUrl,
        authMode,
        authToken,
        capabilityManifestId,
        manifestVersion,
      );
}

extension CloudRuntimeModeWire on CloudRuntimeMode {
  String get wireValue {
    switch (this) {
      case CloudRuntimeMode.selfManaged:
        return 'self_managed';
      case CloudRuntimeMode.managedPro:
        return 'managed_pro';
    }
  }
}

extension CloudRuntimeAuthModeWire on CloudRuntimeAuthMode {
  String get wireValue {
    switch (this) {
      case CloudRuntimeAuthMode.runtimeToken:
        return 'runtime_token';
      case CloudRuntimeAuthMode.hostedSession:
        return 'hosted_session';
    }
  }
}

CloudRuntimeMode cloudRuntimeModeFromWire(Object? value) {
  switch (value) {
    case 'self_managed':
      return CloudRuntimeMode.selfManaged;
    case 'managed_pro':
      return CloudRuntimeMode.managedPro;
  }
  throw FormatException('invalid_runtime_mode', value);
}

CloudRuntimeAuthMode cloudRuntimeAuthModeFromWire(Object? value) {
  switch (value) {
    case 'runtime_token':
      return CloudRuntimeAuthMode.runtimeToken;
    case 'hosted_session':
      return CloudRuntimeAuthMode.hostedSession;
  }
  throw FormatException('invalid_runtime_auth_mode', value);
}
