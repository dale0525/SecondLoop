import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_models.dart';
import 'package:secondloop/core/update/app_update_resolution.dart';

void main() {
  group('app update regressions', () {
    test(
        'compareReleaseTagWithCurrentVersion treats unsupported formats as incomparable',
        () {
      expect(compareReleaseTagWithCurrentVersion('v1.2.3.4', '1.2.3'), 0);
      expect(compareReleaseTagWithCurrentVersion('v1.2.3', '1.2.3.4'), 0);
    });

    test(
        'matchManifestAssetForCurrentPlatform scans Windows manifest candidates for matching app id',
        () {
      final release = <String, Object?>{
        'platforms': <String, Object?>{
          'windows-x64': <Object?>[
            <String, Object?>{
              'name': 'com.secondloop.secondloop-1.0.1-full.nupkg',
              'app_id': 'com.secondloop.secondloop',
              'package_url': 'https://cdn.example.com/default.nupkg',
              'sha256': 'defaultsha',
            },
            <String, Object?>{
              'name': 'com.secondloop.secondloopdev-1.0.1-devwin-full.nupkg',
              'app_id': 'com.secondloop.secondloopdev',
              'package_url': 'https://cdn.example.com/devwin.nupkg',
              'sha256': 'devsha',
            },
          ],
        },
      };

      final asset = matchManifestAssetForCurrentPlatform(
        AppUpdatePlatform.windows,
        release,
        currentArchitecture: 'x64',
        allowHttp: false,
        allowFile: false,
        windowsAppId: 'com.secondloop.secondloopdev',
      );

      expect(asset, isNotNull);
      expect(
          asset!.name, 'com.secondloop.secondloopdev-1.0.1-devwin-full.nupkg');
      expect(
          asset.downloadUri.toString(), 'https://cdn.example.com/devwin.nupkg');
      expect(asset.sha256, 'devsha');
    });

    test(
        'matchManifestAssetForCurrentPlatform accepts manifest-only Windows MSI with matching app id',
        () {
      final release = <String, Object?>{
        'platforms': <String, Object?>{
          'windows-x64': <String, Object?>{
            'name': 'SecondLoop Dev-win.msi',
            'app_id': 'com.secondloop.secondloopdev',
            'package_url': 'https://cdn.example.com/SecondLoop-Dev-win.msi',
            'sha256': 'msisha',
          },
        },
      };

      final asset = matchManifestAssetForCurrentPlatform(
        AppUpdatePlatform.windows,
        release,
        currentArchitecture: 'x64',
        allowHttp: false,
        allowFile: false,
        windowsAppId: 'com.secondloop.secondloopdev',
      );

      expect(asset, isNotNull);
      expect(asset!.name, 'SecondLoop Dev-win.msi');
      expect(
        asset.downloadUri.toString(),
        'https://cdn.example.com/SecondLoop-Dev-win.msi',
      );
      expect(asset.sha256, 'msisha');
    });

    test(
        'matchManifestAssetForCurrentPlatform accepts Windows manifest entry with matching app id when name is omitted',
        () {
      final release = <String, Object?>{
        'platforms': <String, Object?>{
          'windows-x64': <String, Object?>{
            'app_id': 'com.secondloop.secondloopdev',
            'package_url': 'https://cdn.example.com/downloads/latest-package',
            'sha256': 'nupkgsha',
          },
        },
      };

      final asset = matchManifestAssetForCurrentPlatform(
        AppUpdatePlatform.windows,
        release,
        currentArchitecture: 'x64',
        allowHttp: false,
        allowFile: false,
        windowsAppId: 'com.secondloop.secondloopdev',
      );

      expect(asset, isNotNull);
      expect(asset!.name, 'latest-package');
      expect(
        asset.downloadUri.toString(),
        'https://cdn.example.com/downloads/latest-package',
      );
      expect(asset.sha256, 'nupkgsha');
    });

    test(
        'releaseContainsWindowsIdentityMismatch ignores matching manifest-only Windows MSI entries',
        () {
      final release = <String, Object?>{
        'platforms': <String, Object?>{
          'windows-x64': <String, Object?>{
            'name': 'SecondLoop Dev-win.msi',
            'app_id': 'com.secondloop.secondloopdev',
            'package_url': 'https://cdn.example.com/SecondLoop-Dev-win.msi',
          },
        },
      };

      expect(
        releaseContainsWindowsIdentityMismatch(
          release,
          windowsAppId: 'com.secondloop.secondloopdev',
        ),
        isFalse,
      );
    });

    test(
        'releaseContainsWindowsIdentityMismatch ignores mixed Windows entries when one matches the expected app id',
        () {
      final release = <String, Object?>{
        'platforms': <String, Object?>{
          'windows-x64': <Object?>[
            <String, Object?>{
              'name': 'com.secondloop.secondloop-1.0.1-full.nupkg',
              'app_id': 'com.secondloop.secondloop',
              'package_url': 'https://cdn.example.com/prod.nupkg',
            },
            <String, Object?>{
              'name': 'com.secondloop.secondloopdev-1.0.1-devwin-full.nupkg',
              'app_id': 'com.secondloop.secondloopdev',
              'package_url': 'https://cdn.example.com/devwin.nupkg',
            },
          ],
        },
        'assets': <Object?>[
          <String, Object?>{
            'name': 'SecondLoop-win.msi',
            'browser_download_url': 'https://cdn.example.com/prod.msi',
          },
          <String, Object?>{
            'name': 'SecondLoop Dev-win.msi',
            'browser_download_url': 'https://cdn.example.com/dev.msi',
          },
        ],
      };

      expect(
        releaseContainsWindowsIdentityMismatch(
          release,
          windowsAppId: 'com.secondloop.secondloopdev',
        ),
        isFalse,
      );
    });
  });
}
