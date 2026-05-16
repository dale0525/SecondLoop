import 'package:flutter/foundation.dart';

final class QuickCaptureChatSubmission {
  const QuickCaptureChatSubmission({
    required this.id,
    required this.conversationId,
    required this.content,
  });

  final int id;
  final String conversationId;
  final String content;
}

final class QuickCaptureController extends ChangeNotifier {
  bool _visible = false;
  bool _reopenMainWindowOnHide = false;
  bool _openChatRequested = false;
  int _nextSubmissionId = 1;
  final List<QuickCaptureChatSubmission> _pendingChatSubmissions =
      <QuickCaptureChatSubmission>[];

  bool get visible => _visible;

  void show() {
    if (_visible) return;
    _visible = true;
    notifyListeners();
  }

  void hide({
    bool reopenMainWindow = false,
    bool openChat = false,
  }) {
    _reopenMainWindowOnHide = reopenMainWindow;
    _openChatRequested = openChat;

    if (!_visible) {
      if (reopenMainWindow || openChat) {
        notifyListeners();
      }
      return;
    }

    _visible = false;
    notifyListeners();
  }

  bool consumeReopenMainWindowOnHideRequest() {
    final shouldReopen = _reopenMainWindowOnHide;
    _reopenMainWindowOnHide = false;
    return shouldReopen;
  }

  bool consumeOpenChatRequest() {
    final shouldOpenChat = _openChatRequested;
    _openChatRequested = false;
    return shouldOpenChat;
  }

  void submitChatMessage({
    required String conversationId,
    required String content,
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    _pendingChatSubmissions.add(
      QuickCaptureChatSubmission(
        id: _nextSubmissionId++,
        conversationId: conversationId,
        content: trimmed,
      ),
    );
    hide(reopenMainWindow: true, openChat: true);
  }

  QuickCaptureChatSubmission? consumePendingChatSubmission(
    String conversationId,
  ) {
    final index = _pendingChatSubmissions.indexWhere(
      (submission) => submission.conversationId == conversationId,
    );
    if (index == -1) return null;
    return _pendingChatSubmissions.removeAt(index);
  }

  void toggle() => _visible ? hide() : show();
}
