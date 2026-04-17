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
            _formatEventRange(localizations, start, end),
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
