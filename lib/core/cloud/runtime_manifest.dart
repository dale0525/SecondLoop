import 'package:flutter/foundation.dart';

import 'runtime_profile.dart';

@immutable
class CloudRuntimeCapability {
  const CloudRuntimeCapability(this.id);

  final String id;

  @override
  bool operator ==(Object other) =>
      other is CloudRuntimeCapability && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class CloudRuntimeRequiredCapabilities {
  const CloudRuntimeRequiredCapabilities._();

  static const chat = CloudRuntimeCapability('chat');
  static const workingSet = CloudRuntimeCapability('working_set');
  static const llm = CloudRuntimeCapability('llm');
  static const embedding = CloudRuntimeCapability('embedding');
  static const semanticParse = CloudRuntimeCapability('semantic_parse');
  static const mediaUnderstanding =
      CloudRuntimeCapability('media_understanding');
  static const multimodalLlm = CloudRuntimeCapability('multimodal_llm');

  static const all = <CloudRuntimeCapability>[
    chat,
    workingSet,
    llm,
    embedding,
    semanticParse,
    mediaUnderstanding,
    multimodalLlm,
  ];
}

@immutable
class CloudRuntimeManifest {
  const CloudRuntimeManifest({
    required this.manifestVersion,
    required this.runtimeMode,
    required this.apiBaseUrl,
    required this.authMode,
    required this.capabilities,
  });

  final int manifestVersion;
  final CloudRuntimeMode runtimeMode;
  final String apiBaseUrl;
  final CloudRuntimeAuthMode authMode;
  final List<CloudRuntimeCapability> capabilities;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'manifest_version': manifestVersion,
      'runtime_mode': runtimeMode.wireValue,
      'api_base_url': apiBaseUrl,
      'auth_mode': authMode.wireValue,
      'capabilities': capabilities.map((capability) => capability.id).toList(),
    };
  }

  factory CloudRuntimeManifest.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    return CloudRuntimeManifest(
      manifestVersion: (json['manifest_version'] as num?)?.toInt() ?? 0,
      runtimeMode: cloudRuntimeModeFromWire(json['runtime_mode']),
      apiBaseUrl: (json['api_base_url'] as String?) ?? '',
      authMode: cloudRuntimeAuthModeFromWire(json['auth_mode']),
      capabilities: rawCapabilities is List
          ? rawCapabilities
              .map((value) => CloudRuntimeCapability('$value'))
              .toList(growable: false)
          : const <CloudRuntimeCapability>[],
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CloudRuntimeManifest &&
        other.manifestVersion == manifestVersion &&
        other.runtimeMode == runtimeMode &&
        other.apiBaseUrl == apiBaseUrl &&
        other.authMode == authMode &&
        listEquals(other.capabilities, capabilities);
  }

  @override
  int get hashCode => Object.hash(
        manifestVersion,
        runtimeMode,
        apiBaseUrl,
        authMode,
        Object.hashAll(capabilities),
      );
}
