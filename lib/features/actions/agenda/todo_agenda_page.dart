import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_surface.dart';
import '../todo/todo_detail_page.dart';

class TodoAgendaPage extends StatefulWidget {
  const TodoAgendaPage({super.key});

  @override
  State<TodoAgendaPage> createState() => _TodoAgendaPageState();
}

class _TodoAgendaPageState extends State<TodoAgendaPage> {
  Future<List<Todo>>? _todosFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _todosFuture ??= _loadTodos();
  }

  Future<List<Todo>> _loadTodos() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final todos = await backend.listTodos(sessionKey);

    final filtered = todos
        .where((t) =>
            t.dueAtMs != null && t.status != 'done' && t.status != 'dismissed')
        .toList(growable: false);
    filtered.sort((a, b) => a.dueAtMs!.compareTo(b.dueAtMs!));
    return filtered;
  }

  void _refresh() {
    setState(() => _todosFuture = _loadTodos());
  }

  String _statusLabel(BuildContext context, String status) => switch (status) {
        'inbox' => context.t.actions.todoStatus.inbox,
        'open' => context.t.actions.todoStatus.open,
        'in_progress' => context.t.actions.todoStatus.inProgress,
        'done' => context.t.actions.todoStatus.done,
        'dismissed' => context.t.actions.todoStatus.dismissed,
        _ => status,
      };

  String _nextStatusForTap(String status) => switch (status) {
        'inbox' => 'in_progress',
        'open' => 'in_progress',
        'in_progress' => 'done',
        _ => 'open',
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
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('todo_agenda_page'),
      appBar: AppBar(
        title: Text(context.t.actions.agenda.title),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: FutureBuilder<List<Todo>>(
            future: _todosFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    context.t.errors.loadFailed(error: '${snapshot.error}'),
                  ),
                );
              }

              final todos = snapshot.data ?? const <Todo>[];
              if (todos.isEmpty) {
                return Center(child: Text(context.t.actions.agenda.empty));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: todos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final todo = todos[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TodoDetailPage(initialTodo: todo),
                        ),
                      );
                    },
                    child: SlSurface(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            todo.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              SlButton(
                                variant: SlButtonVariant.outline,
                                onPressed: () => _setStatus(
                                  todo,
                                  _nextStatusForTap(todo.status),
                                ),
                                child: Text(_statusLabel(context, todo.status)),
                              ),
                              SlButton(
                                variant: SlButtonVariant.outline,
                                onPressed: () => _setStatus(todo, 'dismissed'),
                                child: Text(
                                  context.t.actions.todoStatus.dismissed,
                                ),
                              ),
                            ],
                          ),
                        ],
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
