import 'package:flutter/material.dart';

typedef TaskHubCardAnchorMeasurement = Rect? Function();

class TaskHubCardAnchorRegistry {
  final Map<String, Rect> _rectByTodoId = <String, Rect>{};
  final Map<String, TaskHubCardAnchorMeasurement> _measureByTodoId =
      <String, TaskHubCardAnchorMeasurement>{};

  Rect? rectFor(String todoId) => _rectByTodoId[todoId];

  void attach(String todoId, TaskHubCardAnchorMeasurement measure) {
    _measureByTodoId[todoId] = measure;
  }

  void detach(String todoId, TaskHubCardAnchorMeasurement measure) {
    final activeMeasurement = _measureByTodoId[todoId];
    if (identical(activeMeasurement, measure)) {
      _measureByTodoId.remove(todoId);
    }
    _rectByTodoId.remove(todoId);
  }

  void update(String todoId, Rect rect) {
    _rectByTodoId[todoId] = rect;
  }

  void remove(String todoId) {
    _rectByTodoId.remove(todoId);
  }

  void refresh({Iterable<String>? todoIds}) {
    final ids = (todoIds ?? _measureByTodoId.keys).toList(growable: false);
    for (final todoId in ids) {
      final measure = _measureByTodoId[todoId];
      if (measure == null) continue;
      final rect = measure();
      if (rect == null) {
        _rectByTodoId.remove(todoId);
        continue;
      }
      _rectByTodoId[todoId] = rect;
    }
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
    widget.registry.attach(widget.todoId, _measureRect);
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
    if (oldWidget.todoId != widget.todoId ||
        oldWidget.registry != widget.registry) {
      oldWidget.registry.detach(oldWidget.todoId, _measureRect);
      widget.registry.attach(widget.todoId, _measureRect);
    }
    _scheduleMeasurement();
  }

  @override
  void dispose() {
    widget.registry.detach(widget.todoId, _measureRect);
    super.dispose();
  }

  Rect? _measureRect() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  void _scheduleMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rect = _measureRect();
      if (rect == null) {
        widget.registry.remove(widget.todoId);
        return;
      }
      widget.registry.update(widget.todoId, rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    return widget.child;
  }
}
