import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release build preserves Gson generic signatures', () {
    final buildGradle = File('android/app/build.gradle').readAsStringSync();
    expect(buildGradle, contains("proguard-rules.pro"));

    final proguardRules = File('android/app/proguard-rules.pro');
    expect(proguardRules.existsSync(), isTrue);

    final rules = proguardRules.readAsStringSync();
    expect(rules, contains('-keepattributes Signature'));
    expect(rules, contains('com.google.gson.reflect.TypeToken'));
    expect(
        rules, contains('com.dexterous.flutterlocalnotifications.models.**'));
  });
}
