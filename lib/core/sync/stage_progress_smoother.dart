class SyncStageProgressSmoother {
  SyncStageProgressSmoother({this.completionHeadroom = 0.98});

  final double completionHeadroom;

  double _lastValue = 0.0;

  double update({required int done, required int total}) {
    if (total <= 0) {
      return _lastValue;
    }

    final raw = (done / total).clamp(0.0, 1.0).toDouble();
    final adjusted = raw >= 1.0 ? completionHeadroom : raw;
    if (adjusted <= _lastValue) {
      return _lastValue;
    }
    _lastValue = adjusted;
    return _lastValue;
  }

  double complete() {
    _lastValue = 1.0;
    return _lastValue;
  }

  void reset() {
    _lastValue = 0.0;
  }
}
