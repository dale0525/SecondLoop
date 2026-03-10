import 'package:flutter/material.dart';

final class KnowledgeDocumentViewerAction {
  const KnowledgeDocumentViewerAction({
    required this.id,
    required this.icon,
    required this.label,
    this.tooltip,
    this.buttonKey,
    this.onPressed,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? tooltip;
  final Key? buttonKey;
  final Future<void> Function()? onPressed;
}
