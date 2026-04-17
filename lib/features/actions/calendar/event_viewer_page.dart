import 'package:flutter/material.dart';

import '../../../src/rust/db.dart';

class EventViewerPage extends StatelessWidget {
  const EventViewerPage({required this.event, super.key});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final start =
        DateTime.fromMillisecondsSinceEpoch(event.startAtMs.toInt()).toLocal();
    final end =
        DateTime.fromMillisecondsSinceEpoch(event.endAtMs.toInt()).toLocal();
    final localTimezone = _formatTimeZoneOffset(start.timeZoneOffset);

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
            _formatEventRange(localizations, start, end, localTimezone),
            key: const ValueKey('event_viewer_time_range'),
          ),
        ],
      ),
    );
  }
}

String _formatEventRange(
  MaterialLocalizations localizations,
  DateTime start,
  DateTime end,
  String timezone,
) {
  final startDate = localizations.formatFullDate(start);
  final startTime =
      localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start));
  final endDate = localizations.formatFullDate(end);
  final endTime = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end));

  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return '$startDate $startTime - $endTime ($timezone)';
  }

  return '$startDate $startTime -> $endDate $endTime ($timezone)';
}

String _formatTimeZoneOffset(Duration offset) {
  final totalMinutes = offset.inMinutes;
  final sign = totalMinutes >= 0 ? '+' : '-';
  final absoluteMinutes = totalMinutes.abs();
  final hours = absoluteMinutes ~/ 60;
  final minutes = absoluteMinutes % 60;
  return 'UTC$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}
