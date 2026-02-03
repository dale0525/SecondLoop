import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SemanticParseDataConsentPrefs {
  static const prefsKey = 'semantic_parse_data_consent_v1';

  // `null` means unset, `false` means explicitly disabled.
  static final ValueNotifier<bool?> value = ValueNotifier<bool?>(null);

  static Future<void> setEnabled(SharedPreferences prefs, bool enabled) async {
    await prefs.setBool(prefsKey, enabled);
    value.value = enabled;
  }
}
