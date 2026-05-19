import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web build ships cross-origin headers for wasm web runtime', () {
    final headers = File('web/_headers').readAsStringSync();

    expect(headers, contains('/app/*'));
    expect(headers, isNot(contains('\n/*\n')));
    expect(
      headers,
      contains('Cross-Origin-Opener-Policy: same-origin'),
    );
    expect(
      headers,
      contains('Cross-Origin-Embedder-Policy: require-corp'),
    );
  });

  test('web index avoids cross-origin Google Fonts under COEP', () {
    final indexHtml = File('web/index.html').readAsStringSync();

    expect(indexHtml, isNot(contains('https://fonts.googleapis.com')));
    expect(indexHtml, isNot(contains('https://fonts.gstatic.com')));
  });

  test('web bootstrap disables Flutter service worker caching', () {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();

    expect(bootstrap, contains("navigator.serviceWorker.getRegistrations()"));
    expect(bootstrap, contains('registration.unregister()'));
    expect(bootstrap, contains('window.location.reload()'));
    expect(bootstrap, isNot(contains('serviceWorkerSettings')));
  });

  test('pixi exposes a local web preview task with cross-origin headers', () {
    final pixi = File('pixi.toml').readAsStringSync();

    expect(pixi, contains('preview-local-web-app'));
    expect(pixi, contains('scripts/preview_local_web_app.sh'));
    expect(pixi, isNot(contains('sync-web-rust-pkg')));
    expect(pixi, isNot(contains('frb-build-web')));
  });

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

  test('web build workflow does not need desktop ffmpeg pruning', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(
      workflow,
      isNot(contains(
          '- name: Prune desktop ffmpeg assets from web build artifact')),
    );
    expect(
      workflow,
      isNot(contains('tools/prune_web_build_ffmpeg.dart')),
    );
  });

  test('web build workflow builds Flutter web directly', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    final buildFlutterStep = workflow.indexOf('- name: Build Flutter Web');

    final uploadArtifactStep = workflow.indexOf('- name: Upload web artifact');

    expect(buildFlutterStep, isNonNegative);
    expect(uploadArtifactStep, greaterThan(buildFlutterStep));
    expect(workflow, isNot(contains('frb-build-web')));
    expect(workflow, isNot(contains('sync-web-rust-pkg')));
  });

  test('web build workflow reruns when Dart tool scripts change', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(workflow, contains('- "tools/**"'));
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

  test('local web CI script builds Flutter web directly', () {
    final script =
        File('scripts/run_flutter_web_ci_local.sh').readAsStringSync();

    final buildFlutter =
        script.indexOf('run_flutter_tool build web --base-href /app/');

    expect(buildFlutter, isNonNegative);
    expect(script, isNot(contains('sync_web_build_rust_pkg.dart')));
    expect(script, isNot(contains('build-web')));
  });

  test('local preview script serves Flutter web build directly', () {
    final script = File('scripts/preview_local_web_app.sh').readAsStringSync();

    final buildFlutter = script.indexOf('flutter build web --base-href /app/');

    expect(buildFlutter, isNonNegative);
    expect(script, contains('tools/serve_web_build_with_headers.py'));
    expect(script, isNot(contains('sync_web_build_rust_pkg.dart')));
    expect(script, isNot(contains('tools/prune_web_build_ffmpeg.dart')));
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

  test('web build workflow also dispatches site deploys after main pushes', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(workflow, contains("github.event_name == 'push'"));
    expect(workflow, contains("github.ref_name == 'main'"));
    expect(workflow, contains('secondloop_web_release_published'));
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
