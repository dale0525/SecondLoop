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
    expect(pixi, contains('sync-web-rust-pkg'));
  });

  test('frb web build task links wasm for shared imported memory', () {
    final pixi = File('pixi.toml').readAsStringSync();

    expect(pixi, contains('frb-build-web'));
    expect(
      pixi,
      contains('flutter pub run flutter_rust_bridge build-web'),
    );
    expect(pixi, isNot(contains('flutter_rust_bridge_codegen build-web')));
    expect(
      pixi,
      contains(r'CC_wasm32_unknown_unknown=\"$PWD/.tool/bin/clang\"'),
    );
    expect(
      pixi,
      contains(r'AR_wasm32_unknown_unknown=\"$PWD/.tool/bin/llvm-ar\"'),
    );
    expect(
      pixi,
      contains(r'RANLIB_wasm32_unknown_unknown=\"$PWD/.tool/bin/llvm-ranlib\"'),
    );
    expect(
      pixi,
      isNot(
        contains(r'CC_wasm32_unknown_unknown=\"$CONDA_PREFIX/bin/clang-21\"'),
      ),
    );
    expect(pixi, contains('--shared-memory'));
    expect(pixi, contains('--import-memory'));
  });

  test(
      'preview frb web build task overrides flutter_rust_bridge atomics default',
      () {
    final pixi = File('pixi.toml').readAsStringSync();

    expect(pixi, contains('frb-build-web-preview'));
    expect(
      pixi,
      contains('+bulk-memory,+mutable-globals'),
    );
    expect(pixi, contains('-Aunstable-features'));
  });

  test('sqlite wasm C build enables atomics and bulk-memory', () {
    final buildRs =
        File('third_party/sqlite-wasm-rs-patched/build.rs').readAsStringSync();

    expect(buildRs, contains('-matomics'));
    expect(buildRs, contains('-mbulk-memory'));
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

  test('web build workflow prepares Rust web package before flutter build', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    final buildRustStep = workflow.indexOf('- name: Build Rust Web package');
    final buildFlutterStep = workflow.indexOf('- name: Build Flutter Web');

    expect(buildRustStep, isNonNegative);
    expect(workflow, contains('pixi run frb-build-web'));
    expect(buildFlutterStep, greaterThan(buildRustStep));
  });

  test('web build workflow syncs the Rust wasm package into build/web', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    final buildFlutterStep = workflow.indexOf('- name: Build Flutter Web');
    final syncPkgStep = workflow.indexOf(
      '- name: Sync Rust wasm package into build/web',
    );
    final uploadArtifactStep = workflow.indexOf('- name: Upload web artifact');

    expect(syncPkgStep, isNonNegative);
    expect(workflow, contains('pixi run sync-web-rust-pkg'));
    expect(syncPkgStep, greaterThan(buildFlutterStep));
    expect(uploadArtifactStep, greaterThan(syncPkgStep));
  });

  test('web build workflow reruns when Dart tool scripts change', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(workflow, contains('- "tools/**"'));
  });

  test('web build workflow reruns when Rust web inputs change', () {
    final workflow = File('.github/workflows/web-build.yml').readAsStringSync();

    expect(workflow, contains('- "rust/**"'));
    expect(workflow, contains('- "scripts/setup_web_rust_toolchain.sh"'));
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

  test('local web CI script builds Rust web package before flutter build', () {
    final script =
        File('scripts/run_flutter_web_ci_local.sh').readAsStringSync();

    final buildRust = script.indexOf(
      'run_flutter_tool pub run flutter_rust_bridge build-web',
    );
    final buildFlutter =
        script.indexOf('run_flutter_tool build web --base-href /app/');
    final syncPkg = script.indexOf('tools/sync_web_build_rust_pkg.dart');

    expect(buildRust, isNonNegative);
    expect(buildFlutter, greaterThan(buildRust));
    expect(syncPkg, greaterThan(buildFlutter));
    expect(script, contains('-o web --release'));
    expect(script, contains('--shared-memory'));
    expect(script, contains('--import-memory'));
  });

  test('local preview script syncs the Rust wasm package after flutter build',
      () {
    final script = File('scripts/preview_local_web_app.sh').readAsStringSync();

    final buildFlutter = script.indexOf('flutter build web --base-href /app/');
    final syncPkg = script.indexOf('tools/sync_web_build_rust_pkg.dart');

    expect(buildFlutter, isNonNegative);
    expect(syncPkg, greaterThan(buildFlutter));
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
