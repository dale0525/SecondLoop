import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/migration_archive_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('export flow saves archive and shows summary',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(tester, saveFilePath: '/tmp/secondloop-migration.zip');
    final backend = _MigrationBackend(
      exportEstimate: const MigrationArchiveExportEstimate(
        schemaVersion: 1,
        archiveKind: 'migration',
        itemCount: 2,
        attachmentCount: 1,
        estimatedSizeBytes: 2048,
      ),
      exportManifest: _manifest(items: 2, attachments: 1),
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await tester.pumpAndSettle();

    expect(find.text('2.0 KB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('migration_archive_export')));
    await tester.pumpAndSettle();

    expect(backend.exportedPaths, ['/tmp/secondloop-migration.zip']);
    expect(find.text('/tmp/secondloop-migration.zip'), findsOneWidget);
    expect(find.byKey(const ValueKey('migration_archive_export_result')),
        findsOneWidget);
  });

  testWidgets(
      'picking import archive shows summary and requires typed confirmation',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      pickedFilePath: '/tmp/import-migration.zip',
      pickedFileSize: 4096,
    );
    final backend = _MigrationBackend(
      exportEstimate: const MigrationArchiveExportEstimate(
        schemaVersion: 1,
        archiveKind: 'migration',
        itemCount: 0,
        attachmentCount: 0,
        estimatedSizeBytes: 0,
      ),
      inspectManifest: _manifest(items: 3, attachments: 2),
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('migration_archive_pick_import')));
    await tester.pumpAndSettle();

    expect(backend.inspectedPaths, ['/tmp/import-migration.zip']);
    expect(find.text('/tmp/import-migration.zip'), findsOneWidget);
    expect(find.byKey(const ValueKey('migration_archive_import_summary')),
        findsOneWidget);
    expect(find.text('4.0 KB'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('migration_archive_start_import')),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('migration_archive_confirm')));
    await tester.pumpAndSettle();

    final stillDisabledButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('migration_archive_start_import')),
    );
    expect(stillDisabledButton.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('migration_archive_confirm_input')),
      'IMPORT',
    );
    await tester.pumpAndSettle();

    final enabledButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('migration_archive_start_import')),
    );
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('summary shows export time in readable local format',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(tester, saveFilePath: '/tmp/secondloop-migration.zip');
    final manifest = _manifest(items: 2, attachments: 1);
    final backend = _MigrationBackend(
      exportEstimate: const MigrationArchiveExportEstimate(
        schemaVersion: 1,
        archiveKind: 'migration',
        itemCount: 2,
        attachmentCount: 1,
        estimatedSizeBytes: 2048,
      ),
      exportManifest: manifest,
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('migration_archive_export')));
    await tester.pumpAndSettle();

    final dt = DateTime.fromMillisecondsSinceEpoch(
      manifest.exportedAtMs.toInt(),
    ).toLocal();
    final expected =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    expect(find.text(expected), findsOneWidget);
    expect(find.text(dt.toIso8601String()), findsNothing);
  });

  testWidgets('confirmed import calls backend and shows imported summary',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(tester, pickedFilePath: '/tmp/import-migration.zip');
    final manifest = _manifest(items: 4, attachments: 2);
    final backend = _MigrationBackend(
      exportEstimate: const MigrationArchiveExportEstimate(
        schemaVersion: 1,
        archiveKind: 'migration',
        itemCount: 0,
        attachmentCount: 0,
        estimatedSizeBytes: 0,
      ),
      inspectManifest: manifest,
      importManifest: manifest,
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('migration_archive_pick_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('migration_archive_confirm')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('migration_archive_confirm_input')),
      'IMPORT',
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('migration_archive_start_import')));
    await tester.pumpAndSettle();

    expect(backend.importedPaths, ['/tmp/import-migration.zip']);
    expect(find.byKey(const ValueKey('migration_archive_import_result')),
        findsOneWidget);
  });

  testWidgets('import progress stage is shown while stream is running',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(tester, pickedFilePath: '/tmp/import-migration.zip');
    final manifest = _manifest(items: 1, attachments: 1);
    final controller = StreamController<String>();
    final backend = _MigrationBackend(
      exportEstimate: const MigrationArchiveExportEstimate(
        schemaVersion: 1,
        archiveKind: 'migration',
        itemCount: 0,
        attachmentCount: 0,
        estimatedSizeBytes: 0,
      ),
      inspectManifest: manifest,
      importManifest: manifest,
      importProgressStream: controller.stream,
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('migration_archive_pick_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('migration_archive_confirm')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('migration_archive_confirm_input')),
      'IMPORT',
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('migration_archive_start_import')));
    await tester.pump();

    controller.add(_progressEvent(
      operation: 'import',
      stage: 'snapshot_created',
      status: 'in_progress',
      done: 1,
      total: 6,
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('migration_archive_progress')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('migration_archive_progress_stage')),
        findsOneWidget);

    controller.add(_resultEvent(operation: 'import', manifest: manifest));
    await controller.close();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('migration_archive_import_result')),
        findsOneWidget);
  });
}

Widget _buildTestApp(AppBackend backend) {
  return AppBackendScope(
    backend: backend,
    child: SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: wrapWithI18n(
        const MaterialApp(
          home: Scaffold(
            body: MigrationArchivePage(),
          ),
        ),
      ),
    ),
  );
}

MigrationArchiveManifest _manifest(
    {required int items, required int attachments}) {
  return MigrationArchiveManifest(
    schemaVersion: 1,
    archiveKind: 'migration',
    exportedAtMs: 1710000000000,
    appVersion: '1.0.0',
    items: List<MigrationArchiveItem>.generate(
      items,
      (index) => MigrationArchiveItem(
        id: 'item_$index',
        entityType: 'message',
        markdownPath: 'items/item_$index.md',
        createdAtMs: 1710000000000 + index,
        updatedAtMs: 1710000001000 + index,
        title: 'Item $index',
        tags: const <String>[],
        status: null,
        extraJson: null,
      ),
    ),
    attachments: List<MigrationArchiveAttachment>.generate(
      attachments,
      (index) => MigrationArchiveAttachment(
        sha256: 'sha_$index',
        archivePath: 'attachments/sha_$index.png',
        originalFilename: 'f$index.png',
        mimeType: 'image/png',
        sizeBytes: 12,
        itemIds: const <String>[],
      ),
    ),
    relations: const <MigrationArchiveRelation>[],
  );
}

String _progressEvent({
  required String operation,
  required String stage,
  required String status,
  required int done,
  required int total,
}) {
  return jsonEncode(<String, Object>{
    'type': 'progress',
    'operation': operation,
    'stage': stage,
    'status': status,
    'done': done,
    'total': total,
  });
}

String _resultEvent({
  required String operation,
  required MigrationArchiveManifest manifest,
}) {
  return jsonEncode(<String, Object?>{
    'type': 'result',
    'operation': operation,
    'manifest': <String, Object?>{
      'schema_version': manifest.schemaVersion,
      'archive_kind': manifest.archiveKind,
      'exported_at_ms': manifest.exportedAtMs,
      'app_version': manifest.appVersion,
      'items': manifest.items
          .map(
            (item) => <String, Object?>{
              'id': item.id,
              'entity_type': item.entityType,
              'markdown_path': item.markdownPath,
              'created_at_ms': item.createdAtMs,
              'updated_at_ms': item.updatedAtMs,
              'title': item.title,
              'tags': item.tags,
              'status': item.status,
              'extra_json': item.extraJson,
            },
          )
          .toList(growable: false),
      'attachments': manifest.attachments
          .map(
            (attachment) => <String, Object?>{
              'sha256': attachment.sha256,
              'archive_path': attachment.archivePath,
              'original_filename': attachment.originalFilename,
              'mime_type': attachment.mimeType,
              'size_bytes': attachment.sizeBytes,
              'item_ids': attachment.itemIds,
            },
          )
          .toList(growable: false),
      'relations': manifest.relations
          .map(
            (relation) => <String, Object?>{
              'from_id': relation.fromId,
              'to_id': relation.toId,
              'relation_type': relation.relationType,
            },
          )
          .toList(growable: false),
    },
  });
}

void _installPicker(
  WidgetTester tester, {
  String? saveFilePath,
  String? pickedFilePath,
  int pickedFileSize = 1,
}) {
  FilePicker? oldPicker;
  try {
    oldPicker = FilePicker.platform;
  } catch (_) {
    oldPicker = null;
  }
  FilePicker.platform = _TestMigrationFilePicker(
    saveFilePath: saveFilePath,
    pickedFilePath: pickedFilePath,
    pickedFileSize: pickedFileSize,
  );
  addTearDown(() {
    FilePicker.platform = oldPicker ?? _TestMigrationFilePicker();
  });
}

final class _MigrationBackend extends TestAppBackend {
  _MigrationBackend({
    required this.exportEstimate,
    this.exportManifest,
    this.inspectManifest,
    this.importManifest,
    this.importProgressStream,
  });

  final MigrationArchiveExportEstimate exportEstimate;
  final MigrationArchiveManifest? exportManifest;
  final MigrationArchiveManifest? inspectManifest;
  final MigrationArchiveManifest? importManifest;
  final Stream<String>? importProgressStream;
  final List<String> exportedPaths = <String>[];
  final List<String> inspectedPaths = <String>[];
  final List<String> importedPaths = <String>[];

  @override
  Future<MigrationArchiveExportEstimate> estimateMigrationArchiveExport(
    Uint8List key,
  ) async =>
      exportEstimate;

  @override
  Future<MigrationArchiveManifest> exportMigrationArchive(
    Uint8List key, {
    required String outputPath,
  }) async {
    exportedPaths.add(outputPath);
    return exportManifest ?? _manifest(items: 0, attachments: 0);
  }

  @override
  Stream<String> runMigrationArchiveExportProgress(
    Uint8List key, {
    required String outputPath,
  }) {
    exportedPaths.add(outputPath);
    return Stream<String>.fromIterable(<String>[
      _progressEvent(
        operation: 'export',
        stage: 'completed',
        status: 'completed',
        done: 5,
        total: 5,
      ),
      _resultEvent(
        operation: 'export',
        manifest: exportManifest ?? _manifest(items: 0, attachments: 0),
      ),
    ]);
  }

  @override
  Future<MigrationArchiveManifest> inspectMigrationArchive({
    required String archivePath,
  }) async {
    inspectedPaths.add(archivePath);
    return inspectManifest ?? _manifest(items: 0, attachments: 0);
  }

  @override
  Future<MigrationArchiveManifest> importMigrationArchive(
    Uint8List key, {
    required String archivePath,
  }) async {
    importedPaths.add(archivePath);
    return importManifest ?? _manifest(items: 0, attachments: 0);
  }

  @override
  Stream<String> runMigrationArchiveImportProgress(
    Uint8List key, {
    required String archivePath,
  }) {
    importedPaths.add(archivePath);
    return importProgressStream ??
        Stream<String>.fromIterable(<String>[
          _progressEvent(
            operation: 'import',
            stage: 'reindex_completed',
            status: 'completed',
            done: 6,
            total: 6,
          ),
          _resultEvent(
            operation: 'import',
            manifest: importManifest ?? _manifest(items: 0, attachments: 0),
          ),
        ]);
  }
}

final class _TestMigrationFilePicker extends FilePicker {
  _TestMigrationFilePicker({
    this.saveFilePath,
    this.pickedFilePath,
    this.pickedFileSize = 1,
  });

  final String? saveFilePath;
  final String? pickedFilePath;
  final int pickedFileSize;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async =>
      saveFilePath;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    bool allowMultiple = false,
    bool allowFolderCreation = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    int compressionQuality = 30,
  }) async {
    if (pickedFilePath == null) return null;
    return FilePickerResult(<PlatformFile>[
      PlatformFile(
          name: 'archive.zip', path: pickedFilePath, size: pickedFileSize),
    ]);
  }
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
