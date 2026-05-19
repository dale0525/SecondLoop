import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/main.dart';

import 'test_backend.dart';

void main() {
  testWidgets('legacy lock preferences do not block startup', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': true,
      'biometric_unlock_enabled_v1': true,
      'master_password_setup_required_v1': true,
      'welcome_guide_seen_v1': true,
    });

    await tester.pumpWidget(MyApp(backend: TestAppBackend()));
    for (var i = 0; i < 30; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .byKey(const ValueKey('agent_conversation_workspace'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(find.byKey(const ValueKey('unlock_password')), findsNothing);
    expect(find.byKey(const ValueKey('setup_password')), findsNothing);
    expect(
      find.byKey(const ValueKey('agent_conversation_workspace')),
      findsOneWidget,
    );
  });
}
