part of 'chat_markdown_editor_page.dart';

typedef ChatMarkdownExportDirectoryResolver = Future<Directory> Function();
typedef ChatMarkdownExportFileMaterializer = Future<File> Function({
  required String extension,
  required Uint8List bytes,
  required String sourceMarkdown,
});

@visibleForTesting
ChatMarkdownExportDirectoryResolver? debugChatMarkdownExportDirectoryResolver;

@visibleForTesting
ChatMarkdownExportFileMaterializer? debugChatMarkdownExportFileMaterializer;

Future<File> _materializeMarkdownExportFile({
  required _MarkdownExportFormat format,
  required Uint8List bytes,
  required String sourceMarkdown,
}) async {
  final debugMaterializer = debugChatMarkdownExportFileMaterializer;
  if (debugMaterializer != null) {
    return debugMaterializer(
      extension: format == _MarkdownExportFormat.png ? 'png' : 'pdf',
      bytes: bytes,
      sourceMarkdown: sourceMarkdown,
    );
  }

  final dir = await _resolveMarkdownExportDirectory();
  final extension = format == _MarkdownExportFormat.png ? 'png' : 'pdf';
  final stem = deriveMarkdownExportFilenameStem(sourceMarkdown);

  var file = File('${dir.path}/$stem.$extension');
  var duplicateIndex = 2;
  while (await file.exists()) {
    file = File('${dir.path}/$stem-$duplicateIndex.$extension');
    duplicateIndex += 1;
  }

  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<Directory> _resolveMarkdownExportDirectory() async {
  final debugResolver = debugChatMarkdownExportDirectoryResolver;
  if (debugResolver != null) {
    final directory = await debugResolver();
    await directory.create(recursive: true);
    return directory;
  }

  final fallbackDownloads = _markdownFallbackDownloadsDirectory();
  if (fallbackDownloads != null) {
    try {
      await fallbackDownloads.create(recursive: true);
      return fallbackDownloads;
    } catch (_) {
      // Ignore and fallback to other directories.
    }
  }

  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      await downloads.create(recursive: true);
      return downloads;
    }
  } catch (_) {
    // Ignore and fallback to app documents.
  }

  final documents = await getApplicationDocumentsDirectory();
  await documents.create(recursive: true);
  return documents;
}

Directory? _markdownFallbackDownloadsDirectory() {
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return Directory('$home/Downloads');
  }

  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null && userProfile.isNotEmpty) {
    return Directory('$userProfile/Downloads');
  }

  return null;
}

bool _shouldShareMarkdownExportedFile() {
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
