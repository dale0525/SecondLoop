import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'task_hub_page_test_helpers.dart';

void main() {
  testWidgets('useLargeViewport returns a cleanup that restores the view',
      (tester) async {
    final originalSize = tester.view.physicalSize;
    final originalDevicePixelRatio = tester.view.devicePixelRatio;

    final cleanup = useLargeViewport(tester);

    expect(tester.view.physicalSize, const Size(1200, 1000));
    expect(tester.view.devicePixelRatio, 1.0);

    cleanup();

    expect(tester.view.physicalSize, originalSize);
    expect(tester.view.devicePixelRatio, originalDevicePixelRatio);
  });
}
