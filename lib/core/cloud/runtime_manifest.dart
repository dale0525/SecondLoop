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

@immutable
class CloudRuntimeSkillAvailability {
  const CloudRuntimeSkillAvailability({
    required this.id,
    required this.status,
    this.provider,
    this.reason,
  });

  final String id;
  final String status;
  final String? provider;
  final String? reason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'status': status,
      if (provider != null) 'provider': provider,
      if (reason != null) 'reason': reason,
    };
  }

  factory CloudRuntimeSkillAvailability.fromJson(Map<String, dynamic> json) {
    return CloudRuntimeSkillAvailability(
      id: (json['id'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      provider: json['provider'] as String?,
      reason: json['reason'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CloudRuntimeSkillAvailability &&
        other.id == id &&
        other.status == status &&
        other.provider == provider &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(id, status, provider, reason);
}

final class CloudRuntimeKnownSkills {
  const CloudRuntimeKnownSkills._();

  static const webResearch = CloudRuntimeSkillAvailability(
    id: 'web-research',
    status: 'ready',
    provider: 'configured',
  );

  static const all = <CloudRuntimeSkillAvailability>[
    webResearch,
  ];
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

  static CloudRuntimeCapability? firstMissingFrom(
    Iterable<CloudRuntimeCapability> capabilities,
  ) {
    final available = capabilities.map((capability) => capability.id).toSet();
    for (final required in all) {
      if (!available.contains(required.id)) {
        return required;
      }
    }
    return null;
  }
}

@immutable
class CloudRuntimeManifest {
  const CloudRuntimeManifest({
    required this.manifestVersion,
    required this.runtimeMode,
    required this.apiBaseUrl,
    required this.authMode,
    required this.capabilities,
    this.skills = const <CloudRuntimeSkillAvailability>[],
  });

  final int manifestVersion;
  final CloudRuntimeMode runtimeMode;
  final String apiBaseUrl;
  final CloudRuntimeAuthMode authMode;
  final List<CloudRuntimeCapability> capabilities;
  final List<CloudRuntimeSkillAvailability> skills;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'manifest_version': manifestVersion,
      'runtime_mode': runtimeMode.wireValue,
      'api_base_url': apiBaseUrl,
      'auth_mode': authMode.wireValue,
      'capabilities': capabilities.map((capability) => capability.id).toList(),
      if (skills.isNotEmpty)
        'skills': skills.map((skill) => skill.toJson()).toList(),
    };
  }

  factory CloudRuntimeManifest.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    final rawSkills = json['skills'];
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
      skills: rawSkills is List
          ? rawSkills
              .whereType<Map>()
              .map(
                (value) => CloudRuntimeSkillAvailability.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList(growable: false)
          : const <CloudRuntimeSkillAvailability>[],
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CloudRuntimeManifest &&
        other.manifestVersion == manifestVersion &&
        other.runtimeMode == runtimeMode &&
        other.apiBaseUrl == apiBaseUrl &&
        other.authMode == authMode &&
        listEquals(other.capabilities, capabilities) &&
        listEquals(other.skills, skills);
  }

  @override
  int get hashCode => Object.hash(
        manifestVersion,
        runtimeMode,
        apiBaseUrl,
        authMode,
        Object.hashAll(capabilities),
        Object.hashAll(skills),
      );
}
