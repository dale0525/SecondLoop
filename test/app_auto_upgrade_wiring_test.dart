import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/app_bootstrap.dart';
import 'package:secondloop/main.dart';
import 'package:secondloop/core/update/auto_upgrade_gate.dart';

import 'test_backend.dart';

class _PendingInitBackend extends TestAppBackend {
  final Completer<void> _completer = Completer<void>();

  @override
  Future<void> init() => _completer.future;
}

void main() {
  testWidgets('auto upgrade wraps app bootstrap while init is still pending',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final backend = _PendingInitBackend();

    await tester.pumpWidget(
      MyApp(
        backend: backend,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AutoUpgradeGate), findsOneWidget);
    expect(find.byType(AppBootstrap), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(AppBootstrap),
        matching: find.byType(AutoUpgradeGate),
      ),
      findsOneWidget,
    );
  });
}
