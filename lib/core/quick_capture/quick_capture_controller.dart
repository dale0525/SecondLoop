import 'package:flutter/foundation.dart';

final class QuickCaptureController extends ChangeNotifier {
  bool _visible = false;
  bool _reopenMainWindowOnHide = false;
  bool _openMainStreamRequested = false;

  bool get visible => _visible;

  void show() {
    if (_visible) return;
    _visible = true;
    notifyListeners();
  }

  void hide({
    bool reopenMainWindow = false,
    bool openMainStream = false,
  }) {
    _reopenMainWindowOnHide = reopenMainWindow;
    _openMainStreamRequested = openMainStream;

    if (!_visible) {
      if (reopenMainWindow || openMainStream) {
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

  bool consumeOpenMainStreamRequest() {
    final shouldOpenMainStream = _openMainStreamRequested;
    _openMainStreamRequested = false;
    return shouldOpenMainStream;
  }

  void toggle() => _visible ? hide() : show();
}
