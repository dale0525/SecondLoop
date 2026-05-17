import 'package:flutter/foundation.dart';

@immutable
final class AttachmentPreviewDescriptor {
  const AttachmentPreviewDescriptor({
    required this.kind,
    required this.url,
    this.thumbnailUrl,
  });

  final String kind;
  final String url;
  final String? thumbnailUrl;
}
