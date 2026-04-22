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
      classifyUpdateFailure('seamless_update_not_supported'),
      UpdateFailureCategory.runtimeUnavailable,
    );
    expect(
      classifyUpdateFailure('macos_update_unsupported_install_location'),
      UpdateFailureCategory.unsupportedInstallLocation,
    );
    expect(
      classifyUpdateFailure('manual_installation_prompt_needed'),
      UpdateFailureCategory.unknown,
    );
  });

  test('SharedPrefsUpdateEventLogger stores and trims recent entries',
      () async {
    SharedPreferences.setMockInitialValues({});
    final logger = SharedPrefsUpdateEventLogger(
      nowUtc: () => DateTime.utc(2026, 3, 14, 0, 0, 30),
    );

    for (var index = 0; index < 25; index += 1) {
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
    expect(recent, hasLength(20));
    expect(recent.first.currentVersion, '1.0.5');
    expect(recent.last.currentVersion, '1.0.24');
  });

  test('SharedPrefsUpdateEventLogger drops stale entries when reading',
      () async {
    SharedPreferences.setMockInitialValues({});
    final logger = SharedPrefsUpdateEventLogger(
      nowUtc: () => DateTime.utc(2026, 3, 14, 12),
    );

    await logger.record(
      UpdateEventRecord(
        type: UpdateEventType.checkSucceeded,
        timestampUtc: DateTime.utc(2026, 3, 1, 12),
        platform: AppUpdatePlatform.macos,
        currentVersion: '1.0.0+1',
      ),
    );
    await logger.record(
      UpdateEventRecord(
        type: UpdateEventType.checkSucceeded,
        timestampUtc: DateTime.utc(2026, 3, 10, 12),
        platform: AppUpdatePlatform.macos,
        currentVersion: '1.0.0+2',
      ),
    );

    final recent = await logger.readRecent();
    expect(recent, hasLength(1));
    expect(recent.single.currentVersion, '1.0.0+2');
  });

  test('SharedPrefsUpdateEventLogger round-trips pending apply dispatch event',
      () async {
    SharedPreferences.setMockInitialValues({});
    final logger = SharedPrefsUpdateEventLogger(
      nowUtc: () => DateTime.utc(2026, 3, 27, 8, 30),
    );

    await logger.record(
      UpdateEventRecord(
        type: UpdateEventType.pendingApplyDispatched,
        timestampUtc: DateTime.utc(2026, 3, 27, 8, 30),
        platform: AppUpdatePlatform.windows,
        message: 'detached_updater_started',
      ),
    );

    final recent = await logger.readRecent();
    expect(recent, hasLength(1));
    expect(recent.single.type, UpdateEventType.pendingApplyDispatched);
    expect(recent.single.message, 'detached_updater_started');
  });

  test('classifyUpdateFailure maps staged restart unsupported errors', () {
    expect(
      classifyUpdateFailure('staged_update_restart_not_supported_for_windows'),
      UpdateFailureCategory.runtimeUnavailable,
    );
  });
}
