import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../i18n/strings.g.dart';
import '../../../ui/sl_surface.dart';
import 'todo_history_summary.dart';

class TodoHistoryPage extends StatefulWidget {
  const TodoHistoryPage({super.key});

  @override
  State<TodoHistoryPage> createState() => _TodoHistoryPageState();
}

class _TodoHistoryPageState extends State<TodoHistoryPage> {
  late WeekWindow _window;
  Future<String>? _summaryFuture;

  @override
  void initState() {
    super.initState();
    _window = naturalWeekWindow(DateTime.now(), offsetWeeks: 2, spanWeeks: 2);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _summaryFuture ??= _loadSummary();
  }

  TodoHistoryLabels _labels(BuildContext context) => TodoHistoryLabels(
        created: context.t.actions.history.sections.created,
        started: context.t.actions.history.sections.started,
        done: context.t.actions.history.sections.done,
        dismissed: context.t.actions.history.sections.dismissed,
      );

  Future<String> _loadSummary() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final labels = _labels(context);

    final todos = await backend.listTodos(sessionKey);
    final titlesById = <String, String>{for (final t in todos) t.id: t.title};

    final createdTodos = await backend.listTodosCreatedInRange(
      sessionKey,
      startAtMsInclusive: _window.startUtcMs,
      endAtMsExclusive: _window.endUtcMsExclusive,
    );
    final activities = await backend.listTodoActivitiesInRange(
      sessionKey,
      startAtMsInclusive: _window.startUtcMs,
      endAtMsExclusive: _window.endUtcMsExclusive,
    );

    final summary = buildTodoHistorySummary(
      window: _window,
      createdTodos: createdTodos,
      activities: activities,
      todoTitlesById: titlesById,
    );

    return formatTodoHistorySummaryText(summary, labels: labels);
  }

  void _setWindow(WeekWindow window) {
    setState(() {
      _window = window;
      _summaryFuture = _loadSummary();
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: _window.startLocal,
        end: _window.endLocalExclusive.subtract(const Duration(days: 1)),
      ),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (picked == null) return;

    final start =
        DateTime(picked.start.year, picked.start.month, picked.start.day);
    final endExclusive =
        DateTime(picked.end.year, picked.end.month, picked.end.day)
            .add(const Duration(days: 1));
    _setWindow(WeekWindow(startLocal: start, endLocalExclusive: endExclusive));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.actions.history.actions.copied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final presets = [
      (
        label: context.t.actions.history.presets.thisWeek,
        window: naturalWeekWindow(now, offsetWeeks: 0, spanWeeks: 1),
        key: 'this_week',
      ),
      (
        label: context.t.actions.history.presets.lastWeek,
        window: naturalWeekWindow(now, offsetWeeks: 1, spanWeeks: 1),
        key: 'last_week',
      ),
      (
        label: context.t.actions.history.presets.lastTwoWeeks,
        window: naturalWeekWindow(now, offsetWeeks: 2, spanWeeks: 2),
        key: 'last_two_weeks',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.actions.history.title),
        actions: [
          FutureBuilder<String>(
            future: _summaryFuture,
            builder: (context, snapshot) {
              final text = snapshot.data;
              if (text == null || text.trim().isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: context.t.actions.history.actions.copy,
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => unawaited(_copy(text)),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presets)
                      ChoiceChip(
                        key: ValueKey('todo_history_${preset.key}'),
                        label: Text(preset.label),
                        selected:
                            preset.window.startLocal == _window.startLocal &&
                                preset.window.endLocalExclusive ==
                                    _window.endLocalExclusive,
                        onSelected: (_) => _setWindow(preset.window),
                      ),
                    ActionChip(
                      label: Text(context.t.actions.history.presets.custom),
                      onPressed: () => unawaited(_pickCustomRange()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<String>(
                    future: _summaryFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            context.t.errors
                                .loadFailed(error: '${snapshot.error}'),
                          ),
                        );
                      }

                      final text = snapshot.data?.trim() ?? '';
                      if (text.isEmpty) {
                        return Center(
                          child: Text(context.t.actions.history.empty),
                        );
                      }

                      return SlSurface(
                        padding: const EdgeInsets.all(12),
                        child: SingleChildScrollView(
                          child: SelectableText(text),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
