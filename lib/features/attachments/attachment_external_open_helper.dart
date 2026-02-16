import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.g.dart';

Future<void> openAttachmentBytesWithSystem(
  BuildContext context, {
  required Future<Uint8List?> Function() loadBytes,
  required String outputStem,
  required String extension,
}) async {
  final bytes = await loadBytes();
  if (bytes == null || bytes.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.errors.loadFailed(error: 'bytes unavailable')),
        duration: const Duration(seconds: 3),
      ),
    );
    return;
  }

  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$outputStem$extension');
    await file.writeAsBytes(bytes, flush: true);

    final launched = await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.errors.loadFailed(error: 'could not open externally'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.errors.loadFailed(error: '$error')),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
