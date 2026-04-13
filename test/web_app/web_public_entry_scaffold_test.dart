import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/ui/sl_surface.dart';
import 'package:secondloop/web_app/web_entry_intent.dart';
import 'package:secondloop/web_app/web_public_entry_scaffold.dart';
import 'package:secondloop/web_app/web_app_theme.dart';

import '../test_i18n.dart';

void main() {
  testWidgets('public entry uses the shared page surface layout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: buildSecondLoopWebTheme(locale: const Locale('en')),
          home: const WebPublicEntryScaffold(
            entryIntent: WebEntryIntent.subscribe,
            signedIn: false,
            child: SizedBox(height: 240, child: Placeholder()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SlPageSurface), findsOneWidget);
    expect(find.text('Subscribe for web access'), findsOneWidget);
  });
}
