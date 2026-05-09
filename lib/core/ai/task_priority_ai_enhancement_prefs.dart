import 'package:shared_preferences/shared_preferences.dart';

final class TaskPriorityAiEnhancementPrefs {
  static const prefsKey = 'task_priority_ai_enhancement_enabled_v1';

  static Future<bool> read() async {
    return true;
  }

  static Future<void> write(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
  }
}
