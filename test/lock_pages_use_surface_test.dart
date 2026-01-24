import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/lock/setup_master_password_page.dart';
import 'package:secondloop/features/lock/unlock_page.dart';
import 'package:secondloop/ui/sl_surface.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Setup master password uses SlSurface', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SetupMasterPasswordPage(onUnlocked: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set master password'), findsOneWidget);
    expect(find.byType(SlSurface), findsWidgets);
  });

  testWidgets('Unlock uses SlSurface', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: UnlockPage(
            onUnlocked: (_) {},
            authenticateBiometrics: () async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlock'), findsOneWidget);
    expect(find.byType(SlSurface), findsWidgets);
  });
}
