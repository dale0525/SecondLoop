import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/app.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';

import 'test_backend.dart';

void main() {
  testWidgets('SecondLoopApp restores persisted managed pro auth on startup',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previousPlatform;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({
      'cloud_uid_v1': 'uid_1',
      'cloud_refresh_token_v1': 'refresh_1',
      'welcome_guide_seen_v1': true,
    });

    try {
      await tester.pumpWidget(SecondLoopApp(backend: TestAppBackend()));
      await tester.pumpAndSettle();

      final cloudAuthScope =
          tester.widget<CloudAuthScope>(find.byType(CloudAuthScope));
      expect(cloudAuthScope.controller.uid, 'uid_1');
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
