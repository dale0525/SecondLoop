import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';

void main() {
  test('managed-vault blob repair diagnostics reject malformed payloads', () {
    expect(
      () => parseManagedVaultBlobRepairQueueDepthForTest('not-json'),
      throwsFormatException,
    );

    expect(
      () => parseManagedVaultBlobRepairQueueDepthForTest('{"unexpected":1}'),
      throwsFormatException,
    );
  });
}
