import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web build workflow passes flutter build args through pixi command_args',
      () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(
      workflow,
      contains('run: pixi run flutter build "web --base-href /app/"'),
    );
    expect(
      workflow,
      isNot(contains('run: pixi run flutter build web --base-href /app/')),
    );
  });

  test('web build workflow quotes step names containing colons', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(
      workflow,
      contains('- name: "Guard: no python runtime process usage"'),
    );
  });

  test('CI workflow generates i18n before web smoke tests', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();

    final generateI18n = workflow.indexOf('- name: Generate i18n');
    final smokeTests = workflow.indexOf('- name: Web smoke tests');

    expect(generateI18n, isNonNegative);
    expect(workflow, contains('run: dart run slang'));
    expect(smokeTests, greaterThan(generateI18n));
  });

  test('web build workflow publishes site deploy dispatch after release', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(workflow, contains('release:'));
    expect(workflow, contains('types: [published]'));
    expect(workflow, contains('SECONDLOOP_SERVER_DISPATCH_TOKEN'));
    expect(workflow, contains('secondloop_web_release_published'));
    expect(workflow, contains('secondloop_web_run_id'));
    expect(workflow, contains(r'repos/$SITE_REPO/dispatches'));
  });
}
