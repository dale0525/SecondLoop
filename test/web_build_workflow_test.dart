import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web build workflow passes flutter build args as one pixi argument', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(
      workflow,
      contains('run: pixi run flutter build "web --base-href /app/"'),
    );
    expect(
      workflow,
      isNot(contains('run: pixi run flutter build web --base-href /app/')),
    );
  });
}
