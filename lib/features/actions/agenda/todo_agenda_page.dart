import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../core/sync/sync_engine_gate.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_delete_confirm_dialog.dart';
import '../../../ui/sl_icon_button.dart';
import '../../../ui/sl_tokens.dart';
import '../time/date_time_picker_dialog.dart';
import '../todo/todo_detail_page.dart';
import '../todo/todo_history_page.dart';

class TodoAgendaPage extends StatefulWidget {
  const TodoAgendaPage({super.key});

  @override
  State<TodoAgendaPage> createState() => _TodoAgendaPageState();
}

final class _LoadMoreDoneMarker {
  const _LoadMoreDoneMarker();
}

const _loadMoreDoneMarker = _LoadMoreDoneMarker();

class _TodoAgendaPageState extends State<TodoAgendaPage> {
  static const _kDoneDotColor = Color(0xFF22C55E);
  static const _kDonePageSize = 20;
  static const _kLoadMoreThresholdPx = 240.0;
  static const List<String> _kSelectableStatuses = <String>[
    'open',
    'in_progress',
    'done',
  ];

  final ScrollController _scrollController = ScrollController();

  Object? _loadError;
  var _loading = true;
  var _loadingMoreDone = false;

  List<Todo> _inProgress = const <Todo>[];
  List<Todo> _open = const <Todo>[];
  List<Todo> _done = const <Todo>[];
  var _doneVisible = 0;
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMoreDone);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMoreDone);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    unawaited(_loadTodos());
  }

  void _maybeLoadMoreDone() {
    if (_loading) return;
    if (_loadingMoreDone) return;
    if (_doneVisible >= _done.length) return;
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > _kLoadMoreThresholdPx) return;
    unawaited(_loadMoreDone());
  }

  Future<void> _loadMoreDone() async {
    if (_loadingMoreDone) return;
    if (_doneVisible >= _done.length) return;

    setState(() => _loadingMoreDone = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    setState(() {
      _doneVisible = math.min(_doneVisible + _kDonePageSize, _done.length);
      _loadingMoreDone = false;
    });
  }

  Future<void> _loadTodos() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _loadingMoreDone = false;
    });

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final todos = await backend.listTodos(sessionKey);

      final scheduled = todos
          .where((t) => t.dueAtMs != null && t.status != 'dismissed')
          .toList(growable: false);

      final inProgress = <Todo>[];
      final open = <Todo>[];
      final done = <Todo>[];
      for (final todo in scheduled) {
        switch (todo.status) {
          case 'in_progress':
            inProgress.add(todo);
            break;
          case 'done':
            done.add(todo);
            break;
          default:
            open.add(todo);
        }
      }

      int compareByDueAt(Todo a, Todo b) => a.dueAtMs!.compareTo(b.dueAtMs!);
      inProgress.sort(compareByDueAt);
      open.sort(compareByDueAt);
      done.sort(compareByDueAt);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _inProgress = inProgress;
        _open = open;
        _done = done;
        _doneVisible = math.min(_kDonePageSize, done.length);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e;
        _inProgress = const <Todo>[];
        _open = const <Todo>[];
        _done = const <Todo>[];
        _doneVisible = 0;
      });
    }
  }

  void _refresh() {
    unawaited(_loadTodos());
  }

  String _statusLabel(BuildContext context, String status) => switch (status) {
        'inbox' => context.t.actions.todoStatus.inbox,
        'open' => context.t.actions.todoStatus.open,
        'in_progress' => context.t.actions.todoStatus.inProgress,
        'done' => context.t.actions.todoStatus.done,
        'dismissed' => context.t.actions.todoStatus.dismissed,
        _ => status,
      };

  Future<void> _setStatus(Todo todo, String newStatus) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.setTodoStatus(
      sessionKey,
      todoId: todo.id,
      newStatus: newStatus,
    );
    if (!mounted) return;
    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    _refresh();
  }

  Future<void> _deleteTodo(Todo todo) async {
    final t = context.t;
    final confirmed = await showSlDeleteConfirmDialog(
      context,
      title: t.actions.todoDelete.dialog.title,
      message: t.actions.todoDelete.dialog.message,
      confirmLabel: t.actions.todoDelete.dialog.confirm,
      confirmButtonKey: ValueKey('todo_agenda_delete_confirm_${todo.id}'),
    );
    if (!mounted) return;
    if (!confirmed) return;

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      await backend.deleteTodo(sessionKey, todoId: todo.id);
      if (!mounted) return;
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _editDue(Todo todo) async {
    final dueAtMs = todo.dueAtMs;
    if (dueAtMs == null) return;

    final dueAtLocal =
        DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final nowLocal = DateTime.now();
    final picked = await showSlDateTimePickerDialog(
      context,
      initialLocal: dueAtLocal,
      firstDate: DateTime(nowLocal.year - 1),
      lastDate: DateTime(nowLocal.year + 3),
      title: context.t.actions.calendar.pickCustom,
      surfaceKey: ValueKey('todo_agenda_due_picker_${todo.id}'),
    );
    if (picked == null || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.upsertTodo(
      sessionKey,
      id: todo.id,
      title: todo.title,
      dueAtMs: picked.toUtc().millisecondsSinceEpoch,
      status: todo.status,
      sourceEntryId: todo.sourceEntryId,
      reviewStage: todo.reviewStage,
      nextReviewAtMs: todo.nextReviewAtMs,
      lastReviewAtMs: todo.lastReviewAtMs,
    );
    if (!mounted) return;
    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    _refresh();
  }

  String? _formatDue(BuildContext context, Todo todo) {
    final dueAtMs = todo.dueAtMs;
    if (dueAtMs == null) return null;
    final dueAtLocal =
        DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatShortDate(dueAtLocal);
    final time =
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(dueAtLocal));
    return '$date $time';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    return Scaffold(
      key: const ValueKey('todo_agenda_page'),
      appBar: AppBar(
        title: Text(context.t.actions.agenda.title),
        actions: [
          IconButton(
            tooltip: context.t.actions.history.title,
            icon: const Icon(Icons.history_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TodoHistoryPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Builder(
            builder: (context) {
              if (_loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_loadError != null) {
                return Center(
                  child: Text(
                    context.t.errors.loadFailed(error: '$_loadError'),
                  ),
                );
              }

              final hasTodos = _inProgress.isNotEmpty ||
                  _open.isNotEmpty ||
                  _doneVisible > 0;
              if (!hasTodos) {
                return Center(child: Text(context.t.actions.agenda.empty));
              }

              final sections = <({
                String label,
                List<Todo> todos,
                int visibleCount,
                bool showLoadMore,
              })>[];

              void addSection({
                required String label,
                required List<Todo> todos,
                required int visibleCount,
                required bool showLoadMore,
              }) {
                if (visibleCount <= 0) return;
                sections.add((
                  label: label,
                  todos: todos,
                  visibleCount: visibleCount,
                  showLoadMore: showLoadMore,
                ));
              }

              addSection(
                label: _statusLabel(context, 'in_progress'),
                todos: _inProgress,
                visibleCount: _inProgress.length,
                showLoadMore: false,
              );
              addSection(
                label: _statusLabel(context, 'open'),
                todos: _open,
                visibleCount: _open.length,
                showLoadMore: false,
              );
              addSection(
                label: _statusLabel(context, 'done'),
                todos: _done,
                visibleCount: _doneVisible,
                showLoadMore: _doneVisible < _done.length,
              );

              var itemCount = 0;
              for (final s in sections) {
                itemCount += 1 + s.visibleCount + (s.showLoadMore ? 1 : 0);
              }

              Object entryAt(int index) {
                var i = index;
                for (final s in sections) {
                  if (i == 0) return s.label;
                  i -= 1;

                  if (i < s.visibleCount) return s.todos[i];
                  i -= s.visibleCount;

                  if (s.showLoadMore) {
                    if (i == 0) return _loadMoreDoneMarker;
                    i -= 1;
                  }
                }
                return '';
              }

              Widget buildDoneLoadMoreRow() {
                final theme = Theme.of(context);
                return Center(
                  child: Padding(
                    key: const ValueKey('todo_agenda_done_load_more'),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _loadingMoreDone
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                );
              }

              return ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: itemCount,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = entryAt(index);
                  if (entry is _LoadMoreDoneMarker) {
                    return buildDoneLoadMoreRow();
                  }

                  if (entry is String) {
                    return Text(
                      entry,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    );
                  }

                  final todo = entry as Todo;
                  final isDone = todo.status == 'done';
                  final dueText = _formatDue(context, todo);
                  final dueAtMs = todo.dueAtMs;
                  final dueAtLocal = dueAtMs == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(
                          dueAtMs,
                          isUtc: true,
                        ).toLocal();
                  final overdue = !isDone &&
                      dueAtLocal != null &&
                      dueAtLocal.isBefore(DateTime.now());
                  final radius = BorderRadius.circular(tokens.radiusLg);
                  final colorScheme = Theme.of(context).colorScheme;
                  final overlay = MaterialStateProperty.resolveWith<Color?>(
                    (states) {
                      if (states.contains(MaterialState.pressed)) {
                        return colorScheme.primary.withOpacity(0.12);
                      }
                      if (states.contains(MaterialState.hovered) ||
                          states.contains(MaterialState.focused)) {
                        return colorScheme.primary.withOpacity(0.08);
                      }
                      return null;
                    },
                  );

                  final dotColor = isDone
                      ? _kDoneDotColor
                      : (overdue ? colorScheme.error : colorScheme.primary);

                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: ValueKey('todo_agenda_item_${todo.id}'),
                        borderRadius: radius,
                        overlayColor: overlay,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TodoDetailPage(initialTodo: todo),
                            ),
                          );
                        },
                        child: Ink(
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: radius,
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Builder(
                              builder: (context) {
                                final isCompactLayout =
                                    MediaQuery.sizeOf(context).width < 680;
                                final statusSelector = _TodoStatusSelector(
                                  statuses: _kSelectableStatuses,
                                  selectedStatus: todo.status,
                                  statusLabelBuilder: (status) =>
                                      _statusLabel(context, status),
                                  buttonKeyBuilder: (status) => ValueKey(
                                    'todo_agenda_set_status_${todo.id}_$status',
                                  ),
                                  onSelected: (status) =>
                                      _setStatus(todo, status),
                                );
                                final deleteButton = SlIconButton(
                                  key: ValueKey(
                                    'todo_agenda_delete_${todo.id}',
                                  ),
                                  tooltip: context.t.common.actions.delete,
                                  icon: Icons.delete_outline_rounded,
                                  size: isCompactLayout ? 36 : 38,
                                  iconSize: 18,
                                  color: colorScheme.error,
                                  overlayBaseColor: colorScheme.error,
                                  borderColor: colorScheme.error.withOpacity(
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.32
                                        : 0.22,
                                  ),
                                  onPressed: () => _deleteTodo(todo),
                                );

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isCompactLayout) ...[
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: dotColor,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              todo.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 22,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 20),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: statusSelector),
                                            const SizedBox(width: 8),
                                            deleteButton,
                                          ],
                                        ),
                                      ),
                                    ] else
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: dotColor,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              todo.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          statusSelector,
                                          const SizedBox(width: 8),
                                          deleteButton,
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 24,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                    if (dueText != null) ...[
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 20),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 520,
                                          ),
                                          child: _TodoDueChip(
                                            chipKey: ValueKey(
                                              'todo_agenda_due_${todo.id}',
                                            ),
                                            icon: overdue
                                                ? Icons.warning_rounded
                                                : Icons.schedule_rounded,
                                            label: dueText,
                                            highlight: overdue
                                                ? _DueChipHighlight.danger
                                                : _DueChipHighlight.neutral,
                                            onPressed: () => _editDue(todo),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _TodoStatusSelector extends StatelessWidget {
  const _TodoStatusSelector({
    required this.statuses,
    required this.selectedStatus,
    required this.statusLabelBuilder,
    required this.onSelected,
    this.buttonKeyBuilder,
  });

  final List<String> statuses;
  final String selectedStatus;
  final String Function(String status) statusLabelBuilder;
  final ValueChanged<String> onSelected;
  final Key? Function(String status)? buttonKeyBuilder;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final status in statuses)
          _TodoStatusButton(
            buttonKey: buttonKeyBuilder?.call(status),
            label: statusLabelBuilder(status),
            selected: status == selectedStatus,
            onPressed: () {
              if (status == selectedStatus) return;
              onSelected(status);
            },
          ),
      ],
    );
  }
}

final class _TodoStatusButton extends StatelessWidget {
  const _TodoStatusButton({
    required this.label,
    required this.onPressed,
    required this.selected,
    this.buttonKey,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;
    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      final base = selected ? colorScheme.primary : colorScheme.onSurface;
      if (states.contains(MaterialState.pressed)) {
        return base.withOpacity(0.16);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return base.withOpacity(0.1);
      }
      return null;
    });

    final foreground =
        selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final border = selected
        ? colorScheme.primary.withOpacity(
            theme.brightness == Brightness.dark ? 0.58 : 0.4,
          )
        : tokens.borderSubtle;
    final background = selected
        ? colorScheme.primary.withOpacity(
            theme.brightness == Brightness.dark ? 0.2 : 0.08,
          )
        : tokens.surface2;

    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        side: BorderSide(color: border),
      ).copyWith(overlayColor: overlay),
      icon: Icon(
        selected ? Icons.check_rounded : Icons.circle_outlined,
        size: 16,
        color: foreground,
      ),
      label: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum _DueChipHighlight {
  neutral,
  danger,
}

final class _TodoDueChip extends StatelessWidget {
  const _TodoDueChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.highlight,
    this.chipKey,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final _DueChipHighlight highlight;
  final Key? chipKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final fg = highlight == _DueChipHighlight.danger
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final border = highlight == _DueChipHighlight.danger
        ? colorScheme.error.withOpacity(isDark ? 0.4 : 0.28)
        : tokens.borderSubtle.withOpacity(isDark ? 0.9 : 0.95);

    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      final base = highlight == _DueChipHighlight.danger
          ? colorScheme.error
          : colorScheme.primary;
      if (states.contains(MaterialState.pressed)) {
        return base.withOpacity(0.16);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return base.withOpacity(0.12);
      }
      return null;
    });

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: OutlinedButton.icon(
        key: chipKey,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: tokens.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          side: BorderSide(color: border),
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(overlayColor: overlay),
        icon: Icon(icon, size: 16, color: fg),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
