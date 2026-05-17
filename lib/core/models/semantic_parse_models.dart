class TodoCandidate {
  final String id;
  final String title;
  final String status;
  final String? dueLocalIso;

  const TodoCandidate({
    required this.id,
    required this.title,
    required this.status,
    this.dueLocalIso,
  });

  @override
  int get hashCode =>
      id.hashCode ^ title.hashCode ^ status.hashCode ^ dueLocalIso.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoCandidate &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          status == other.status &&
          dueLocalIso == other.dueLocalIso;
}
