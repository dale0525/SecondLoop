import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/update_event_log.dart';

void main() {
  test('classifyUpdateFailure maps common failure categories', () {
    expect(
      classifyUpdateFailure('http_404'),
      UpdateFailureCategory.network,
    );
    expect(
      classifyUpdateFailure('invalid_update_manifest_signature'),
      UpdateFailureCategory.signature,
    );
    expect(
      classifyUpdateFailure('update_asset_sha256_mismatch'),
      UpdateFailureCategory.integrity,
    );
    expect(
      classifyUpdateFailure('windows_velopack_unavailable'),
      UpdateFailureCategory.runtimeUnavailable,
    );
    expect(
      classifyUpdateFailure('macos_update_unsupported_install_location'),
      UpdateFailureCategory.unsupportedInstallLocation,
    );
  });

  test('SharedPrefsUpdateEventLogger stores and trims recent entries',
      () async {
    SharedPreferences.setMockInitialValues({});
    final logger = SharedPrefsUpdateEventLogger();

    for (var index = 0; index < 55; index += 1) {
      await logger.record(
        UpdateEventRecord(
          type: UpdateEventType.checkStarted,
          timestampUtc: DateTime.utc(2026, 3, 14, 0, 0, index),
          platform: AppUpdatePlatform.windows,
          currentVersion: '1.0.$index',
        ),
      );
    }

    final recent = await logger.readRecent();
    expect(recent, hasLength(50));
    expect(recent.first.currentVersion, '1.0.5');
    expect(recent.last.currentVersion, '1.0.54');
  });
}
