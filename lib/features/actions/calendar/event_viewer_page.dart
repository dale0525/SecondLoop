import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';

class EventViewerPage extends StatelessWidget {
  const EventViewerPage({required this.event, super.key});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final localStart =
        DateTime.fromMillisecondsSinceEpoch(event.startAtMs.toInt()).toLocal();
    final localEnd =
        DateTime.fromMillisecondsSinceEpoch(event.endAtMs.toInt()).toLocal();
    final originalStart =
        _resolveEventTimeInOriginalTimezone(event.startAtMs.toInt(), event.tz);
    final originalEnd =
        _resolveEventTimeInOriginalTimezone(event.endAtMs.toInt(), event.tz);
    final t = context.t.actions.calendar;

    return Scaffold(
      key: const ValueKey('event_viewer_page'),
      appBar: AppBar(
        title: Text(event.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            event.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          SelectableText(
            t.localTimeRange(
              range: _formatEventRange(localizations, localStart, localEnd),
            ),
            key: const ValueKey('event_viewer_time_range'),
          ),
          if (originalStart != null && originalEnd != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              t.timezoneTimeRange(
                timezone: event.tz,
                range: _formatEventRange(
                    localizations, originalStart, originalEnd),
              ),
              key: const ValueKey('event_viewer_original_time_range'),
            ),
          ],
          if (event.tz.trim().isNotEmpty &&
              (originalStart == null || originalEnd == null)) ...[
            const SizedBox(height: 12),
            SelectableText(
              event.tz,
              key: const ValueKey('event_viewer_timezone'),
            ),
          ],
        ],
      ),
    );
  }
}

bool _timezoneDatabaseInitialized = false;

String _formatEventRange(
  MaterialLocalizations localizations,
  DateTime start,
  DateTime end,
) {
  final startDate = localizations.formatFullDate(start);
  final startTime =
      localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start));
  final endDate = localizations.formatFullDate(end);
  final endTime = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end));

  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return '$startDate $startTime - $endTime';
  }

  return '$startDate $startTime -> $endDate $endTime';
}

Duration? _parseEventTimezoneOffset(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final uppercase = trimmed.toUpperCase();
  if (uppercase == 'UTC' || uppercase == 'Z') {
    return Duration.zero;
  }

  final normalized =
      uppercase.startsWith('UTC') ? trimmed.substring(3).trim() : trimmed;
  final match = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(normalized);
  if (match == null) return null;

  final sign = match.group(1) == '-' ? -1 : 1;
  final hours = int.tryParse(match.group(2) ?? '');
  final minutes = int.tryParse(match.group(3) ?? '');
  if (hours == null || minutes == null) return null;

  return Duration(minutes: sign * ((hours * 60) + minutes));
}

DateTime? _resolveEventTimeInOriginalTimezone(
  int millisecondsSinceEpoch,
  String rawTimezone,
) {
  final offset = _parseEventTimezoneOffset(rawTimezone);
  if (offset != null) {
    return _formatEventTimeInOffset(millisecondsSinceEpoch, offset);
  }

  final location = _resolveIanaTimezone(rawTimezone);
  if (location == null) return null;

  return tz.TZDateTime.fromMillisecondsSinceEpoch(
    location,
    millisecondsSinceEpoch,
  );
}

tz.Location? _resolveIanaTimezone(String rawTimezone) {
  final trimmed = rawTimezone.trim();
  if (trimmed.isEmpty) return null;

  _ensureTimezoneDatabaseInitialized();
  if (!_timezoneDatabaseInitialized) return null;

  try {
    return tz.getLocation(trimmed);
  } catch (_) {
    return null;
  }
}

void _ensureTimezoneDatabaseInitialized() {
  if (_timezoneDatabaseInitialized) return;
  try {
    tz_data.initializeTimeZones();
    _timezoneDatabaseInitialized = true;
  } catch (_) {
    // Ignore initialization failures and fall back to local-only rendering.
  }
}

DateTime _formatEventTimeInOffset(int millisecondsSinceEpoch, Duration offset) {
  return DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
    isUtc: true,
  ).add(offset);
}
