import 'dart:convert';

enum TodoRecurrenceFrequency {
  daily,
  weekly,
  monthly,
  yearly,
}

extension TodoRecurrenceFrequencyWire on TodoRecurrenceFrequency {
  String get wireValue => switch (this) {
        TodoRecurrenceFrequency.daily => 'daily',
        TodoRecurrenceFrequency.weekly => 'weekly',
        TodoRecurrenceFrequency.monthly => 'monthly',
        TodoRecurrenceFrequency.yearly => 'yearly',
      };
}

TodoRecurrenceFrequency? todoRecurrenceFrequencyFromWireValue(String value) {
  return switch (value) {
    'daily' => TodoRecurrenceFrequency.daily,
    'weekly' => TodoRecurrenceFrequency.weekly,
    'monthly' => TodoRecurrenceFrequency.monthly,
    'yearly' => TodoRecurrenceFrequency.yearly,
    _ => null,
  };
}

final class TodoRecurrenceRule {
  const TodoRecurrenceRule({
    required this.frequency,
    required this.interval,
  });

  final TodoRecurrenceFrequency frequency;
  final int interval;

  String toJsonString() {
    return jsonEncode(<String, Object>{
      'freq': frequency.wireValue,
      'interval': interval,
    });
  }

  static TodoRecurrenceRule? tryParseJson(String? ruleJson) {
    if (ruleJson == null) return null;

    final trimmed = ruleJson.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final rawFreq = decoded['freq'];
      if (rawFreq is! String) {
        return null;
      }
      final frequency = todoRecurrenceFrequencyFromWireValue(rawFreq);
      if (frequency == null) {
        return null;
      }

      final rawInterval = decoded['interval'];
      final interval = switch (rawInterval) {
        int value => value,
        num value when value == value.toInt() => value.toInt(),
        _ => -1,
      };
      if (interval <= 0) {
        return null;
      }

      return TodoRecurrenceRule(
        frequency: frequency,
        interval: interval,
      );
    } catch (_) {
      return null;
    }
  }
}
