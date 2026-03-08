import 'package:shared_preferences/shared_preferences.dart';

final class ExternalImportPhaseBPrefs {
  static const String consentKey = 'external_import_phase_b_consent_v1';

  static Future<bool> readConsentGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(consentKey) ?? false;
  }

  static Future<void> saveConsentGranted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(consentKey, true);
  }
}
