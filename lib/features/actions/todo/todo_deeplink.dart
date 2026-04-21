class TodoDeepLink {
  const TodoDeepLink({required this.todoId});

  final String todoId;
}

TodoDeepLink? parseTodoDeepLink(String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  if (uri.scheme.toLowerCase() != 'secondloop') return null;
  if (uri.host.toLowerCase() != 'todo') return null;

  final todoId = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first.trim();
  if (todoId.isEmpty) return null;

  return TodoDeepLink(todoId: todoId);
}
