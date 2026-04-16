import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

int _lineCount(String path) {
  return File(path).readAsLinesSync().length;
}

void main() {
  test('managed vault rust entry stays below the repository file-size cap', () {
    expect(
      _lineCount('rust/src/sync/managed_vault.rs'),
      lessThanOrEqualTo(1000),
    );
  });

  test('rag rust entry stays below the repository file-size cap', () {
    expect(
      _lineCount('rust/src/rag/mod.rs'),
      lessThanOrEqualTo(1000),
    );
  });
}
