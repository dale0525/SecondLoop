import 'dart:typed_data';

import 'package:flutter/widgets.dart';

class SessionScope extends InheritedWidget {
  const SessionScope({
    required this.sessionKey,
    required this.lock,
    required super.child,
    super.key,
  });

  final Uint8List sessionKey;
  final VoidCallback lock;

  static SessionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>();

  static SessionScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(SessionScope oldWidget) =>
      oldWidget.sessionKey != sessionKey;
}
