import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/ui/sl_surface.dart';
import 'package:secondloop/web_app/web_app_shell.dart';
import 'package:secondloop/web_app/web_app_theme.dart';

import '../test_i18n.dart';

void main() {
  testWidgets('Web app shell uses a NavigationRail on wide screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: buildSecondLoopWebTheme(locale: const Locale('en')),
          home: WebAppShell(
            title: 'SecondLoop Web',
            selectedIndex: 0,
            destinations: const <WebAppShellDestination>[
              WebAppShellDestination(
                label: 'Chat',
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
              ),
              WebAppShellDestination(
                label: 'Files',
                icon: Icons.folder_outlined,
                selectedIcon: Icons.folder,
              ),
            ],
            onDestinationSelected: (_) {},
            child: const Placeholder(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Web app shell uses a NavigationBar on narrow screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: buildSecondLoopWebTheme(locale: const Locale('en')),
          home: WebAppShell(
            title: 'SecondLoop Web',
            selectedIndex: 0,
            destinations: const <WebAppShellDestination>[
              WebAppShellDestination(
                label: 'Chat',
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
              ),
              WebAppShellDestination(
                label: 'Files',
                icon: Icons.folder_outlined,
                selectedIcon: Icons.folder,
              ),
            ],
            onDestinationSelected: (_) {},
            child: const Placeholder(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets(
      'Web app shell keeps rail and content visually grouped on wide screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: buildSecondLoopWebTheme(locale: const Locale('en')),
          home: WebAppShell(
            title: 'SecondLoop Web',
            selectedIndex: 0,
            destinations: const <WebAppShellDestination>[
              WebAppShellDestination(
                label: 'Chat',
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
              ),
              WebAppShellDestination(
                label: 'Files',
                icon: Icons.folder_outlined,
                selectedIcon: Icons.folder,
              ),
            ],
            onDestinationSelected: (_) {},
            child: const Placeholder(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final railRect = tester.getRect(find.byType(NavigationRail));
    final pageSurfaceConstrainedRect = tester.getRect(
      find.descendant(
        of: find.byType(SlPageSurface),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox && widget.constraints.maxWidth == 1120,
        ),
      ),
    );
    final visualGap = pageSurfaceConstrainedRect.left - railRect.right;

    expect(visualGap, lessThan(220));
  });
}
