import 'package:flutter/foundation.dart';

enum UpdateRestartBlockReason {
  editing,
  aiAnalysis,
}

final class UpdateRestartBlockToken {
  UpdateRestartBlockToken._(this._reason);

  final UpdateRestartBlockReason _reason;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    UpdateRestartActivity._release(_reason);
  }
}

final class UpdateRestartActivity {
  static final ValueNotifier<int> _editingBlocks = ValueNotifier<int>(0);
  static final ValueNotifier<int> _aiAnalysisBlocks = ValueNotifier<int>(0);
  static final Listenable _changes = Listenable.merge(<Listenable>[
    _editingBlocks,
    _aiAnalysisBlocks,
  ]);

  static Listenable get changes => _changes;

  static bool get canRestartNow =>
      _editingBlocks.value <= 0 && _aiAnalysisBlocks.value <= 0;

  static UpdateRestartBlockToken blockEditing() {
    _editingBlocks.value += 1;
    return UpdateRestartBlockToken._(UpdateRestartBlockReason.editing);
  }

  static UpdateRestartBlockToken blockAiAnalysis() {
    _aiAnalysisBlocks.value += 1;
    return UpdateRestartBlockToken._(UpdateRestartBlockReason.aiAnalysis);
  }

  static void _release(UpdateRestartBlockReason reason) {
    switch (reason) {
      case UpdateRestartBlockReason.editing:
        if (_editingBlocks.value > 0) {
          _editingBlocks.value -= 1;
        }
      case UpdateRestartBlockReason.aiAnalysis:
        if (_aiAnalysisBlocks.value > 0) {
          _aiAnalysisBlocks.value -= 1;
        }
    }
  }

  @visibleForTesting
  static void resetForTests() {
    _editingBlocks.value = 0;
    _aiAnalysisBlocks.value = 0;
  }
}
