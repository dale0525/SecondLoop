part of 'chat_page.dart';

extension _ChatPageStateMethodsOFocusRouting on _ChatPageState {
  bool _isTransientPendingMessage(Message message) =>
      message.id.startsWith('pending_') && message.id != _kFailedAskMessageId;

  void _unfocusBeforeRoutePush() {
    if (_isDesktopPlatform) return;
    _inputFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<T?> _pushRouteFromChat<T>(Route<T> route) {
    _unfocusBeforeRoutePush();
    return Navigator.of(context).push(route);
  }

  Future<T?> _showModalBottomSheetFromChat<T>({
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool showDragHandle = false,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    _unfocusBeforeRoutePush();
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: builder,
    );
  }

  Future<T?> _showDialogFromChat<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    _unfocusBeforeRoutePush();
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  Future<T?> _showMenuFromChat<T>({
    required RelativeRect position,
    required List<PopupMenuEntry<T>> items,
  }) {
    _unfocusBeforeRoutePush();
    return showMenu<T>(
      context: context,
      position: position,
      items: items,
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.pixels <= _kBottomThresholdPx;
    final shouldRefreshOnReturnToBottom =
        atBottom && !_isAtBottom && _hasUnseenNewMessages;
    if (atBottom != _isAtBottom) {
      _setState(() {
        _isAtBottom = atBottom;
        if (atBottom) _hasUnseenNewMessages = false;
      });
      if (shouldRefreshOnReturnToBottom) {
        _refresh();
      }
    }

    if (!_usePagination) return;

    final remaining = position.maxScrollExtent - position.pixels;
    if (remaining > _kLoadMoreThresholdPx) return;
    unawaited(_loadOlderMessages());
  }

  Future<void> _loadEmbeddingsDataConsentPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kEmbeddingsDataConsentPrefsKey)) return;

    final value = prefs.getBool(_kEmbeddingsDataConsentPrefsKey) ?? false;
    if (!mounted) return;
    _setState(() => _cloudEmbeddingsConsented = value);
  }
}
