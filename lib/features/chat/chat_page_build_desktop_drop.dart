part of 'chat_page.dart';

extension _ChatPageStateDesktopDropComposer on _ChatPageState {
  Widget _buildDesktopDropTargetComposer(
    BuildContext context, {
    required SlTokens tokens,
    required ColorScheme colorScheme,
    required Widget child,
  }) {
    if (!_isDesktopPlatform) return child;
    bool routeIsCurrent() => ModalRoute.of(context)?.isCurrent ?? true;

    return DropTarget(
      key: const ValueKey('chat_desktop_drop_target'),
      onDragEntered: (_) {
        if (!routeIsCurrent()) return;
        if (!mounted || _desktopDropActive) return;
        _setState(() => _desktopDropActive = true);
      },
      onDragExited: (_) {
        if (!routeIsCurrent()) return;
        if (!mounted || !_desktopDropActive) return;
        _setState(() => _desktopDropActive = false);
      },
      onDragDone: (detail) {
        if (!routeIsCurrent()) return;
        if (mounted && _desktopDropActive) {
          _setState(() => _desktopDropActive = false);
        }
        unawaited(_addDroppedDesktopFilesToComposerDraft(detail.files));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          border: Border.all(
            color: _desktopDropActive
                ? colorScheme.primary.withOpacity(0.5)
                : Colors.transparent,
            width: _desktopDropActive ? 2 : 1,
          ),
          color: _desktopDropActive
              ? colorScheme.primaryContainer.withOpacity(0.16)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }
}
