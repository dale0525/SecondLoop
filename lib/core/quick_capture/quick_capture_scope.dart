import 'package:flutter/widgets.dart';

import 'quick_capture_controller.dart';

class QuickCaptureScope extends InheritedWidget {
  const QuickCaptureScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final QuickCaptureController controller;

  static QuickCaptureController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No QuickCaptureScope found in widget tree');
    return controller!;
  }

  static QuickCaptureController? maybeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<QuickCaptureScope>();
    return scope?.controller;
  }

  @override
  bool updateShouldNotify(QuickCaptureScope oldWidget) =>
      oldWidget.controller != controller;
}
