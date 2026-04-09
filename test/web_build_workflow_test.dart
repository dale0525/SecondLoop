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

  test('web build workflow prunes desktop ffmpeg assets before upload', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(
      workflow,
      contains('- name: Prune desktop ffmpeg assets from web build artifact'),
    );
    expect(
      workflow,
      contains('pixi run flutter pub "run tools/prune_web_build_ffmpeg.dart"'),
    );
    expect(
      workflow,
      isNot(contains('rm -rf build/web/assets/assets/bin/ffmpeg')),
    );
    expect(
      workflow.indexOf(
        '- name: Prune desktop ffmpeg assets from web build artifact',
      ),
      lessThan(workflow.indexOf('- name: Upload web artifact')),
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
    expect(workflow, contains('release_tag'));
    expect(workflow, contains(r'repos/$SITE_REPO/dispatches'));
  });

  test('web build workflow dispatches stable artifact selectors only', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(workflow, contains('secondloop_web_run_id'));
    expect(workflow, contains('secondloop_web_head_sha'));
    expect(
      workflow,
      isNot(contains('client_payload[secondloop_web_ref]')),
    );
    expect(
      workflow,
      isNot(contains('github.event.release.target_commitish')),
    );
  });

  test('web build workflow only builds for strict app release tags', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(workflow, contains('release.tag_name'));
    expect(workflow, contains(r'if [[ "$GITHUB_EVENT_NAME" == '));
    expect(workflow, contains(r'^v[0-9]+\.[0-9]+\.[0-9]+$'));
    expect(
      workflow,
      contains('Skipping web build for non-app release tag'),
    );
    expect(workflow, isNot(contains(r'if [[ "${{ github.event_name }}" == ')));
  });

  test('web build workflow skips release dispatch when site token is unset',
      () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(
      workflow,
      contains(
        'SECONDLOOP_SERVER_DISPATCH_TOKEN is not configured; skipping site deploy dispatch.',
      ),
    );
  });
}
