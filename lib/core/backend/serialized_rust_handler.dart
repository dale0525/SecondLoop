import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

final class SerializedRustHandler extends BaseHandler {
  Future<void> _tail = Future<void>.value();

  @visibleForTesting
  Future<T> schedule<T>(Future<T> Function() action) {
    final scheduled = _tail.catchError((_) {}).then((_) => action());
    _tail = scheduled.then<void>((_) {}, onError: (_, __) {});
    return scheduled;
  }

  @override
  Future<S> executeNormal<S, E extends Object>(NormalTask<S, E> task) {
    return schedule(() => super.executeNormal(task));
  }
}
