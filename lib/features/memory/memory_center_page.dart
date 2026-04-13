import 'package:flutter/widgets.dart';

import '../knowledge_center/knowledge_center_page.dart';

class MemoryCenterPage extends KnowledgeCenterPage {
  const MemoryCenterPage({super.key});

  static Future<void> open(BuildContext context) {
    return KnowledgeCenterPage.open(context);
  }
}
