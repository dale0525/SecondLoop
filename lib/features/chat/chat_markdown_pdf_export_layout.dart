import 'dart:ui';

Rect buildPdfPreviewContentRect(Size pageSize) {
  return Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);
}
