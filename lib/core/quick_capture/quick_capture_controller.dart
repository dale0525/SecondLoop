import 'package:flutter/foundation.dart';

final class QuickCaptureController extends ChangeNotifier {
  bool _visible = false;
  bool _reopenMainWindowOnHide = false;
  bool _openChatRequested = false;

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

  void toggle() => _visible ? hide() : show();
}
