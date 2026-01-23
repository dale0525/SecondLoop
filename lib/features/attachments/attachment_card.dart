import 'package:flutter/material.dart';

import '../../src/rust/db.dart';

class AttachmentCard extends StatelessWidget {
  const AttachmentCard({
    required this.attachment,
    this.onTap,
    super.key,
  });

  final Attachment attachment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    final byteLen = attachment.byteLen.toInt();
    final subtitle = _formatBytes(byteLen);

    final child = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(isImage ? Icons.image_outlined : Icons.attach_file),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.mimeType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return Card(child: child);
    }

    return Card(
      child: InkWell(
        onTap: onTap,
        child: child,
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}
