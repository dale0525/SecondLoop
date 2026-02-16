final class DesktopTrayClickController {
  DesktopTrayClickController({
    required this.onLeftClick,
    required this.onRightClick,
  });

  final Future<void> Function() onLeftClick;
  final Future<void> Function() onRightClick;

  Future<void> handleLeftMouseDown() => onLeftClick();

  Future<void> handleRightMouseDown() => onRightClick();
}
