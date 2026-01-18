import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/i18n/locale_prefs.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLocaleBootstrap.resetForTests();
    binding.platformDispatcher.localeTestValue = const Locale('en', 'US');
  });

  await testMain();
}
