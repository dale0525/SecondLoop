import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/i18n/strings.g.dart';

import 'package:secondloop/features/media_backup/cloud_media_download.dart';
import 'package:secondloop/features/media_backup/cloud_media_download_ui.dart';

import 'test_i18n.dart';

void main() {
  test('UI mapper parses legacy state error codes', () {
    expect(
      cloudMediaDownloadFailureReasonFromError(
        StateError('media_download_requires_wifi'),
      ),
      CloudMediaDownloadFailureReason.cellularRestricted,
    );

    expect(
      cloudMediaDownloadFailureReasonFromError(
        StateError('media_download_authRequired'),
      ),
      CloudMediaDownloadFailureReason.authRequired,
    );
  });

  test('UI mapper parses typed cloud download failures', () {
    expect(
      cloudMediaDownloadFailureReasonFromError(
        const CloudMediaDownloadFailureException(
          CloudMediaDownloadFailureReason.remoteMissing,
        ),
      ),
      CloudMediaDownloadFailureReason.remoteMissing,
    );
  });

  test('UI mapper classifies failure reasons consistently', () {
    expect(
      cloudMediaDownloadUiErrorFromFailureReason(
        CloudMediaDownloadFailureReason.cellularRestricted,
      ),
      CloudMediaDownloadUiError.wifiOnlyBlocked,
    );

    expect(
      cloudMediaDownloadUiErrorFromFailureReason(
        CloudMediaDownloadFailureReason.authRequired,
      ),
      CloudMediaDownloadUiError.signInRequired,
    );

    expect(
      cloudMediaDownloadUiErrorFromFailureReason(
        CloudMediaDownloadFailureReason.networkOffline,
      ),
      CloudMediaDownloadUiError.previewUnavailable,
    );

    expect(
      cloudMediaDownloadUiErrorFromFailureReason(
        CloudMediaDownloadFailureReason.none,
      ),
      isNull,
    );
  });

  testWidgets('UI message localizes readonly web media copy', (tester) async {
    late BuildContext buildContext;

    await tester.pumpWidget(
      wrapWithI18n(
        Builder(
          builder: (context) {
            buildContext = context;
            return const MaterialApp(home: SizedBox.shrink());
          },
        ),
      ),
    );

    expect(
      cloudMediaDownloadUiMessage(
        buildContext,
        CloudMediaDownloadUiError.previewUnavailable,
        isWeb: true,
        isReadonlyMedia: true,
      ),
      contains('Continue processing in the app'),
    );

    LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

    await tester.pumpWidget(
      wrapWithI18n(
        Builder(
          builder: (context) {
            buildContext = context;
            return const MaterialApp(home: SizedBox.shrink());
          },
        ),
      ),
    );

    expect(
      cloudMediaDownloadUiMessage(
        buildContext,
        CloudMediaDownloadUiError.previewUnavailable,
        isWeb: true,
        isReadonlyMedia: true,
      ),
      contains('继续在 App 中处理'),
    );
  });
}
