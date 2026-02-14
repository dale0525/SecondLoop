import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/desktop/desktop_window_display_controller.dart';

void main() {
  test('hideToTray hides app from taskbar before hiding window', () async {
    final calls = <String>[];
    final controller = DesktopWindowDisplayController(
      adapter: _FakeWindowDisplayAdapter(calls),
    );

    await controller.hideToTray();

    expect(calls, <String>['skip:true', 'hide']);
  });

  test('showMainWindow restores taskbar icon before focusing window', () async {
    final calls = <String>[];
    final controller = DesktopWindowDisplayController(
      adapter: _FakeWindowDisplayAdapter(calls),
    );

    await controller.showMainWindow();

    expect(calls, <String>['skip:false', 'show', 'focus']);
  });
}

final class _FakeWindowDisplayAdapter implements WindowDisplayAdapter {
  _FakeWindowDisplayAdapter(this.calls);

  final List<String> calls;

  @override
  Future<void> focus() async {
    calls.add('focus');
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
  }

  @override
  Future<void> setSkipTaskbar(bool skipTaskbar) async {
    calls.add('skip:$skipTaskbar');
  }

  @override
  Future<void> show() async {
    calls.add('show');
  }
}
