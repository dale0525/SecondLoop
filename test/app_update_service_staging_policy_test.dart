import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/windows/velopack_update_client.dart';

class _AvailableWindowsStagedUpdateClient implements WindowsStagedUpdateClient {
  @override
  bool hasPendingUpdate() => false;

  @override
  bool isAvailable() => true;

  @override
  Future<void> applyPendingAndRestart({required int waitPid}) async {}

  @override
  Future<PendingUpdateStartupResult> applyPendingOnStartup(
      {required int waitPid}) async {
    return const PendingUpdateStartupResult.noPendingUpdate();
  }

  @override
  String? pendingUpdatePackagePath() => null;

  @override
  String? pendingUpdateVersion() => null;

  @override
  Future<void> installAssetAndRestart(Uri assetDownloadUri,
      {required int waitPid}) async {}

  @override
  Future<void> stageAsset(Uri assetDownloadUri) async {}
}

void main() {
  test('canStageSilentlyForNextLaunch accepts staged-next-launch updates', () {
    final service = AppUpdateService(
      platformOverride: AppUpdatePlatform.windows,
      windowsStagedUpdateClient: _AvailableWindowsStagedUpdateClient(),
    );
    final update = AppUpdateAvailability(
      currentVersion: '1.0.0+1',
      latestTag: 'v1.1.0',
      releasePageUri: Uri.parse(
        'https://github.com/dale0525/SecondLoop/releases/tag/v1.1.0',
      ),
      installMode: AppUpdateInstallMode.stagedNextLaunch,
      asset: AppUpdateAsset(
        name: 'com.secondloop.secondloop-1.1.0-full.nupkg',
        downloadUri: Uri.parse('https://cdn.example.com/win.nupkg'),
      ),
    );

    expect(service.canStageSilentlyForNextLaunch(update), isTrue);
  });
}
