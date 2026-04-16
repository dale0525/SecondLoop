import 'dart:io';

void main() {
  final sourceDir = Directory('rust/web/pkg');
  final targetDir = Directory('build/web/pkg');

  if (!sourceDir.existsSync()) {
    stderr.writeln(
      'Missing Rust web package at ${sourceDir.path}. Run `pixi run frb-build-web` first.',
    );
    exitCode = 1;
    return;
  }

  final buildWebDir = Directory('build/web');
  if (!buildWebDir.existsSync()) {
    stderr.writeln(
      'Missing Flutter web build at ${buildWebDir.path}. Run `flutter build web` first.',
    );
    exitCode = 1;
    return;
  }

  if (targetDir.existsSync()) {
    targetDir.deleteSync(recursive: true);
  }
  targetDir.createSync(recursive: true);

  for (final entity in sourceDir.listSync(recursive: false)) {
    final name = entity.uri.pathSegments.last;
    final destinationPath = '${targetDir.path}/$name';
    if (entity is File) {
      entity.copySync(destinationPath);
    } else if (entity is Directory) {
      _copyDirectory(entity, Directory(destinationPath));
    }
  }

  stdout.writeln(
    'Synced Rust web package from ${sourceDir.path} to ${targetDir.path}.',
  );
}

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync(recursive: false)) {
    final name = entity.uri.pathSegments.last;
    final destinationPath = '${destination.path}/$name';
    if (entity is File) {
      entity.copySync(destinationPath);
    } else if (entity is Directory) {
      _copyDirectory(entity, Directory(destinationPath));
    }
  }
}
