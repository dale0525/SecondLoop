import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime-first client paths do not import Rust or native backend APIs',
      () {
    final files = _runtimeClientFiles();
    expect(files, isNotEmpty);

    const forbidden = [
      'src/rust',
      'flutter_rust_bridge',
      'rust_core.',
      'rust_attachments.',
      'runtime_compat/api',
      'NativeAppBackend',
      'SyncEngineScope',
      'LocalRuntimeAudioTranscribeClient',
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source,
          isNot(contains(token)),
          reason: '${file.path} must not contain $token',
        );
      }
    }
  });

  test('runtime-first app shell does not mount local media processing gates',
      () {
    final appShell = File('lib/app/app.dart').readAsStringSync();

    const forbidden = [
      'media_enrichment_gate.dart',
      'share_ingest_gate.dart',
      'share_intent_listener.dart',
      'MediaEnrichmentGate',
      'ShareIngestGate',
      'ShareIntentListener',
    ];

    for (final token in forbidden) {
      expect(
        appShell,
        isNot(contains(token)),
        reason: 'lib/app/app.dart must not mount $token in the normal app flow',
      );
    }
  });

  test('runtime-first app shell does not mount local AI processing gates', () {
    final appShell = File('lib/app/app.dart').readAsStringSync();

    const forbidden = [
      'DetachedAskRecoveryGate',
      'TodoFollowupGenerationGate',
      'MessageEmbeddingsIndexGate',
      'EmbeddingsIndexGate',
      'detached_ask_recovery_gate.dart',
      'todo_followup_generation_gate.dart',
      'message_embeddings_index_gate.dart',
      'embeddings_index_gate.dart',
    ];

    for (final token in forbidden) {
      expect(
        appShell,
        isNot(contains(token)),
        reason: 'lib/app/app.dart must not mount local AI runtime token $token',
      );
    }
  });

  test('runtime-first app shell does not mount legacy sync gates', () {
    final appShell = File('lib/app/app.dart').readAsStringSync();

    const forbidden = [
      'SyncEngineGate',
      'CloudSyncSwitchPromptGate',
      'SyncKeyManager',
      'sync_engine_gate.dart',
      'cloud_sync_switch_prompt_gate.dart',
      'sync_key_manager.dart',
    ];

    for (final token in forbidden) {
      expect(
        appShell,
        isNot(contains(token)),
        reason: 'lib/app/app.dart must not mount local sync token $token',
      );
    }
  });

  test(
      'runtime-first settings and attachment display do not import runtime APIs',
      () {
    final files = [
      File('lib/features/settings/settings_page.dart'),
      File('lib/features/settings/diagnostics_page.dart'),
      File('lib/features/attachments/attachment_card.dart'),
    ];

    const forbidden = [
      'runtime_compat/api',
      'rust_',
      'getNativeAppDir',
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source,
          isNot(contains(token)),
          reason: '${file.path} must not depend on local runtime token $token',
        );
      }
    }
  });

  test('AI settings does not expose retired local media runtime settings', () {
    final files = [
      File('lib/features/settings/ai_settings_page.dart'),
      File('lib/features/settings/ai_settings_page_ui.dart'),
    ];

    const forbidden = [
      'media_annotation_settings_page.dart',
      'MediaAnnotationSettingsPage',
      'focusMediaLocalCapabilityCard',
      'mediaLocalCapability',
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source,
          isNot(contains(token)),
          reason: '${file.path} must not expose retired local media runtime '
              'settings in the runtime-first AI settings flow',
        );
      }
    }
  });

  test('runtime-first backend shims do not import runtime compat APIs', () {
    final files = [
      ...Directory('lib/core/backend')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      File('lib/web_app/web_native_app_backend.dart'),
      File('lib/web_app/web_native_app_backend_managed_vault_push.dart'),
    ];

    const forbidden = [
      'runtime_compat/api',
      'rust_core.',
      'rust_attachments.',
      'rust_web_sync.',
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source,
          isNot(contains(token)),
          reason: '${file.path} must not depend on retired runtime token '
              '$token',
        );
      }
    }
  });

  test('main app dependency graph does not include Rust or FRB', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final pubspecLock = File('pubspec.lock').readAsStringSync();
    final flutterPlugins = File('.flutter-plugins').existsSync()
        ? File('.flutter-plugins').readAsStringSync()
        : '';
    final flutterPluginDependencies =
        File('.flutter-plugins-dependencies').existsSync()
            ? File('.flutter-plugins-dependencies').readAsStringSync()
            : '';
    final generatedPluginRegistrants = [
      File('linux/flutter/generated_plugins.cmake'),
      File('windows/flutter/generated_plugins.cmake'),
      File('macos/Flutter/GeneratedPluginRegistrant.swift'),
    ].where((file) => file.existsSync()).map((file) => file.readAsStringSync());

    for (final forbidden in [
      'flutter_rust_bridge',
      'secondloop_rust:',
      'rust_builder',
      'super_clipboard',
      'super_native_extensions',
      'irondash_engine_context',
      'irondash_message_channel',
    ]) {
      expect(pubspec, isNot(contains(forbidden)));
      expect(pubspecLock, isNot(contains(forbidden)));
      expect(flutterPlugins, isNot(contains(forbidden)));
      expect(flutterPluginDependencies, isNot(contains(forbidden)));
      for (final registrant in generatedPluginRegistrants) {
        expect(registrant, isNot(contains(forbidden)));
      }
    }

    for (final path in [
      'lib/src/rust',
      'rust',
      'rust_builder',
      'third_party/flutter-rust-bridge-patched',
      'tools/sync_web_build_rust_pkg.dart',
      'rust-toolchain.toml',
    ]) {
      expect(
        Directory(path).existsSync() || File(path).existsSync(),
        isFalse,
        reason: '$path must not be part of the main app runtime tree',
      );
    }
  });

  test('main app Dart sources do not import generated Rust bindings', () {
    final files = [
      ..._dartFiles(Directory('lib')),
      ..._dartFiles(Directory('test')),
    ].where((file) =>
        !file.path.endsWith('no_rust_dependency_for_runtime_client_test.dart'));
    const forbidden = [
      'src/rust',
      'flutter_rust_bridge',
      'secondloop_rust',
      'rust_builder',
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source,
          isNot(contains(token)),
          reason: '${file.path} must not contain $token',
        );
      }
    }
  });

  test('app build and release entrypoints do not run Rust toolchains', () {
    final files = [
      File('pixi.toml'),
      File('.github/workflows/ci.yml'),
      File('.github/workflows/web-build.yml'),
      File('.github/workflows/release.yml'),
      File('scripts/run_full_ci_parallel.sh'),
      File('scripts/run_flutter_ci_local.sh'),
      File('scripts/run_flutter_web_ci_local.sh'),
      File('scripts/run_flutter_test_shard.sh'),
      File('scripts/run_windows.ps1'),
      File('scripts/run_with_android_env.sh'),
      File('scripts/package_windows_msi.ps1'),
      File('scripts/package_windows_velopack.ps1'),
      File('.githooks/pre-commit'),
    ].where((file) => file.existsSync());

    const forbidden = [
      'flutter_rust_bridge',
      'secondloop_rust',
      'rust_builder',
      'frb-build-web',
      'sync-web-rust-pkg',
      'setup_rustup.sh',
      'setup_web_rust_toolchain.sh',
      'run_full_rust_ci_local.sh',
      'run_rust_builder_package_tests.sh',
      'dtolnay/rust-toolchain',
      'CARGOKIT',
      'BINDGEN_EXTRA_CLANG_ARGS',
      'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR',
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source,
          isNot(contains(token)),
          reason: '${file.path} must not contain $token',
        );
      }
    }
  });

  test('app run and release entrypoints do not prepare local media runtimes',
      () {
    final files = [
      File('pixi.toml'),
      File('.github/workflows/release.yml'),
      File('.github/workflows/web-build.yml'),
      File('scripts/run_windows.ps1'),
      File('scripts/package_windows_msi.ps1'),
      File('scripts/package_windows_velopack.ps1'),
    ].where((file) => file.existsSync());

    const forbidden = [
      'prepare_desktop_runtime.dart',
      'sync_desktop_runtime_to_appdir.dart',
      'prepare_bundled_ffmpeg.dart',
      'setup_ffmpeg_macos.sh',
      'setup_ffmpeg_windows.ps1',
      'brew install ffmpeg',
      'assets/bin/ffmpeg',
      'SECONDLOOP_DESKTOP_RUNTIME_TAG',
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source,
          isNot(contains(token)),
          reason: '${file.path} must not prepare local media runtime token '
              '$token in normal app run/release paths',
        );
      }
    }
  });

  test('pubspec does not bundle local ffmpeg or desktop runtime assets', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    const forbidden = [
      'assets/bin/ffmpeg',
      'assets/ocr/desktop_runtime',
      'assets/ocr/desktop_runtime/models',
      'assets/ocr/desktop_runtime/onnxruntime',
      'assets/ocr/desktop_runtime/whisper',
    ];

    for (final token in forbidden) {
      expect(
        pubspec,
        isNot(contains(token)),
        reason: 'pubspec.yaml must not bundle $token',
      );
    }
  });
}

List<File> _runtimeClientFiles() {
  return [
    ..._dartFiles(Directory('lib/core/cloud')),
    ..._dartFiles(Directory('lib/core/offline_edit')),
    ..._dartFiles(Directory('lib/features/notes')),
    File('lib/features/attachments/attachment_preview_descriptor.dart'),
    File('lib/features/attachments/attachment_storage_controller.dart'),
    File('lib/features/settings/ai_settings_page.dart'),
    File('lib/features/settings/cloud_runtime_mode_page.dart'),
    File('lib/features/settings/vault_usage_card.dart'),
  ];
}

Iterable<File> _dartFiles(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}
