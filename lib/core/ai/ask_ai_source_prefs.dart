import 'package:shared_preferences/shared_preferences.dart';

import 'ai_routing.dart';

enum AskAiSourcePreference {
  auto,
  cloud,
  byok,
}

final class AskAiSourcePrefs {
  static const prefsKey = 'ask_ai_source_preference_v1';

  static Future<AskAiSourcePreference> read() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(prefsKey));
  }

  static Future<void> write(AskAiSourcePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _encode(preference);
    if (raw == null) {
      await prefs.remove(prefsKey);
      return;
    }
    await prefs.setString(prefsKey, raw);
  }

  static AskAiSourcePreference _decode(String? raw) {
    return switch (raw?.trim() ?? '') {
      'cloud' => AskAiSourcePreference.cloud,
      'byok' => AskAiSourcePreference.byok,
      _ => AskAiSourcePreference.auto,
    };
  }

  static String? _encode(AskAiSourcePreference preference) {
    return switch (preference) {
      AskAiSourcePreference.auto => null,
      AskAiSourcePreference.cloud => 'cloud',
      AskAiSourcePreference.byok => 'byok',
    };
  }
}

AskAiRouteKind applyAskAiSourcePreference(
  AskAiRouteKind defaultRoute,
  AskAiSourcePreference preference, {
  bool hasByokWhenCloudRoute = false,
}) {
  return switch (preference) {
    AskAiSourcePreference.auto => defaultRoute,
    AskAiSourcePreference.cloud => defaultRoute == AskAiRouteKind.cloudGateway
        ? AskAiRouteKind.cloudGateway
        : AskAiRouteKind.needsSetup,
    AskAiSourcePreference.byok => defaultRoute == AskAiRouteKind.byok
        ? AskAiRouteKind.byok
        : (defaultRoute == AskAiRouteKind.cloudGateway && hasByokWhenCloudRoute)
            ? AskAiRouteKind.byok
            : AskAiRouteKind.needsSetup,
  };
}
