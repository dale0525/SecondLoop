import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/vault_reset_error.dart';

void main() {
  test('recognizes structured reset cleanup failure code', () {
    expect(
      isVaultResetCommittedCleanupFailure(
        StateError(
          '$kVaultResetCommittedCleanupFailureCode: attachment cleanup',
        ),
      ),
      isTrue,
    );
  });

  test('keeps recognizing legacy reset cleanup failure messages', () {
    expect(
      isVaultResetCommittedCleanupFailure(
        StateError(
          'filesystem cleanup failed after vault reset commit: attachment cleanup',
        ),
      ),
      isTrue,
    );
  });

  test('does not classify unrelated reset errors as committed cleanup failures',
      () {
    expect(
      isVaultResetCommittedCleanupFailure(
        StateError('reset failed before commit'),
      ),
      isFalse,
    );
  });
}
