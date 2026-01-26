import 'package:flutter/foundation.dart';

@immutable
class TodoThreadMatch {
  const TodoThreadMatch({required this.todoId, required this.distance});

  final String todoId;
  final double distance;
}
