import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/sync/stage_progress_smoother.dart';

void main() {
  test('keeps progress monotonic when total grows late', () {
    final smoother = SyncStageProgressSmoother();

    expect(smoother.update(done: 0, total: 2), 0.0);
    expect(smoother.update(done: 1, total: 2), 0.5);
    expect(smoother.update(done: 2, total: 2), 0.98);
    expect(smoother.update(done: 2, total: 3), 0.98);
    expect(smoother.update(done: 3, total: 3), 0.98);
  });

  test('complete reaches 100 percent explicitly', () {
    final smoother = SyncStageProgressSmoother();

    smoother.update(done: 1, total: 1);
    expect(smoother.complete(), 1.0);
  });

  test('reporter keeps headroom until explicit completion', () {
    final seen = <double>[];
    final reporter = SyncStageProgressReporter((value) => seen.add(value));

    reporter.onProgress(1, 1);
    expect(seen, [0.98]);

    reporter.complete();
    expect(seen, [0.98, 1.0]);
  });
}
