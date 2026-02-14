abstract interface class WindowDisplayAdapter {
  Future<void> setSkipTaskbar(bool skipTaskbar);

  Future<void> show();

  Future<void> focus();

  Future<void> hide();
}

final class DesktopWindowDisplayController {
  DesktopWindowDisplayController({required WindowDisplayAdapter adapter})
      : _adapter = adapter;

  final WindowDisplayAdapter _adapter;

  Future<void> showMainWindow() async {
    await _adapter.setSkipTaskbar(false);
    await _adapter.show();
    await _adapter.focus();
  }

  Future<void> hideToTray() async {
    await _adapter.setSkipTaskbar(true);
    await _adapter.hide();
  }
}
