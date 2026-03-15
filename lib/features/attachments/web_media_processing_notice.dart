import 'package:flutter/material.dart';

import '../../core/content_enrichment/docx_ocr_policy.dart';

const String _kSecondLoopVideoManifestMimeType =
    'application/x.secondloop.video+json';

bool needsAppProcessingInWeb(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  return normalized.startsWith('video/') ||
      normalized.startsWith('audio/') ||
      normalized == 'application/pdf' ||
      isDocxMimeType(normalized) ||
      normalized == _kSecondLoopVideoManifestMimeType;
}

class WebMediaProcessingNotice extends StatelessWidget {
  const WebMediaProcessingNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sync_problem_outlined,
              color: colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Continue processing in the app',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Existing cloud results stay available here. If a file still needs OCR, decoding, or transcoding, open it in the app to continue processing.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
