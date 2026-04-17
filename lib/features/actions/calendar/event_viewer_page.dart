import 'package:flutter/material.dart';

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
    final originalOffset = _parseEventTimezoneOffset(event.tz);
    final originalStart = originalOffset == null
        ? null
        : _formatEventTimeInOffset(event.startAtMs.toInt(), originalOffset);
    final originalEnd = originalOffset == null
        ? null
        : _formatEventTimeInOffset(event.endAtMs.toInt(), originalOffset);

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
            'Local: ${_formatEventRange(localizations, localStart, localEnd)}',
            key: const ValueKey('event_viewer_time_range'),
          ),
          if (originalStart != null && originalEnd != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              '${event.tz}: ${_formatEventRange(localizations, originalStart, originalEnd)}',
              key: const ValueKey('event_viewer_original_time_range'),
            ),
          ],
          if (event.tz.trim().isNotEmpty) ...[
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
  final trimmed = raw.trim().toUpperCase();
  if (trimmed.isEmpty) return null;
  if (trimmed == 'UTC' || trimmed == 'Z') {
    return Duration.zero;
  }

  final normalized =
      trimmed.startsWith('UTC') ? trimmed.substring(3).trim() : trimmed;
  final match = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(normalized);
  if (match == null) return null;

  final sign = match.group(1) == '-' ? -1 : 1;
  final hours = int.tryParse(match.group(2) ?? '');
  final minutes = int.tryParse(match.group(3) ?? '');
  if (hours == null || minutes == null) return null;

  return Duration(minutes: sign * ((hours * 60) + minutes));
}

DateTime _formatEventTimeInOffset(int millisecondsSinceEpoch, Duration offset) {
  return DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
    isUtc: true,
  ).add(offset);
}
