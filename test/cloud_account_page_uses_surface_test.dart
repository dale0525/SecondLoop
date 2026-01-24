import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/ui/sl_surface.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Cloud account page uses SlSurface for the sign-in form',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(home: CloudAccountPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPage), findsOneWidget);
    expect(find.byType(SlSurface), findsWidgets);
  });
}
