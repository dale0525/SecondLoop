import 'package:flutter/material.dart';

class TaskHubCardAnchorRegistry {
  final Map<String, Rect> _rectByTodoId = <String, Rect>{};

  Rect? rectFor(String todoId) => _rectByTodoId[todoId];

  void update(String todoId, Rect rect) {
    _rectByTodoId[todoId] = rect;
  }

  void remove(String todoId) {
    _rectByTodoId.remove(todoId);
  }
}

class TaskHubCardAnchor extends StatefulWidget {
  const TaskHubCardAnchor({
    required this.todoId,
    required this.registry,
    required this.child,
    super.key,
  });

  final String todoId;
  final TaskHubCardAnchorRegistry registry;
  final Widget child;

  @override
  State<TaskHubCardAnchor> createState() => _TaskHubCardAnchorState();
}

class _TaskHubCardAnchorState extends State<TaskHubCardAnchor> {
  @override
  void initState() {
    super.initState();
    _scheduleMeasurement();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMeasurement();
  }

  @override
  void didUpdateWidget(covariant TaskHubCardAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todoId != widget.todoId) {
      oldWidget.registry.remove(oldWidget.todoId);
    }
    _scheduleMeasurement();
  }

  @override
  void dispose() {
    widget.registry.remove(widget.todoId);
    super.dispose();
  }

  void _scheduleMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        return;
      }
      final topLeft = renderObject.localToGlobal(Offset.zero);
      widget.registry.update(widget.todoId, topLeft & renderObject.size);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    return widget.child;
  }
}
