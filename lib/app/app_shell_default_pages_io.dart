import 'package:flutter/material.dart';

import 'app_shell_default_pages_shared.dart' as shared_defaults;

Widget buildDefaultChatTab(
  BuildContext context, {
  required bool isActive,
}) {
  return shared_defaults.buildSharedDefaultChatTab(
    context,
    isActive: isActive,
  );
}

Widget buildDefaultSettingsTab(
  BuildContext context, {
  required bool isActive,
}) {
  return shared_defaults.buildSharedDefaultSettingsTab(
    context,
    isActive: isActive,
  );
}

Widget buildDefaultMemoryTab(
  BuildContext context, {
  required bool isActive,
}) {
  return shared_defaults.buildSharedDefaultMemoryTab(
    context,
    isActive: isActive,
  );
}

Widget buildDefaultReviewTab(
  BuildContext context, {
  required bool isActive,
}) {
  return shared_defaults.buildSharedDefaultReviewTab(
    context,
    isActive: isActive,
  );
}
