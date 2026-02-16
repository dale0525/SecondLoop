part of 'chat_page.dart';

extension _ChatPageStateInputKeyHandler on _ChatPageState {
  // ignore: deprecated_member_use
  KeyEventResult _handleComposerOnKey(FocusNode node, RawKeyEvent event) {
    // ignore: deprecated_member_use
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    bool isShortcutChar(String char) =>
        char == 'a' || char == 'c' || char == 'v' || char == 'x';

    String? keyChar;
    final keyLabel = event.data.keyLabel;
    if (keyLabel.length == 1) {
      final lowered = keyLabel.toLowerCase();
      if (isShortcutChar(lowered)) {
        keyChar = lowered;
      }
    }
    if (keyChar == null) {
      final rawChar = event.character;
      if (rawChar != null && rawChar.length == 1) {
        final lowered = rawChar.toLowerCase();
        if (isShortcutChar(lowered)) {
          keyChar = lowered;
        }
      }
    }

    final composing = _controller.value.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;

    final hardware = HardwareKeyboard.instance;
    final modifierData = event.data;
    final metaPressed = hardware.isMetaPressed ||
        modifierData.isModifierPressed(ModifierKey.metaModifier);
    final controlPressed = hardware.isControlPressed ||
        modifierData.isModifierPressed(ModifierKey.controlModifier);
    final shiftPressed = hardware.isShiftPressed ||
        modifierData.isModifierPressed(ModifierKey.shiftModifier);
    final hasModifier = metaPressed || controlPressed;

    final isPaste = key == LogicalKeyboardKey.paste ||
        ((keyChar == 'v' || key == LogicalKeyboardKey.keyV) && hasModifier);
    if (isPaste) {
      unawaited(_pasteIntoChatInput());
      return KeyEventResult.handled;
    }

    final isSelectAll = hasModifier &&
        (keyChar == 'a' || (keyChar == null && key == LogicalKeyboardKey.keyA));
    if (isSelectAll) {
      final textLength = _controller.value.text.length;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: textLength,
      );
      return KeyEventResult.handled;
    }

    final isCopy = (key == LogicalKeyboardKey.copy ||
            keyChar == 'c' ||
            key == LogicalKeyboardKey.keyC) &&
        hasModifier;
    if (isCopy) {
      final value = _controller.value;
      final selection = value.selection;
      if (selection.isValid && !selection.isCollapsed) {
        final start = selection.start;
        final end = selection.end;
        final normalizedStart = start < end ? start : end;
        final normalizedEnd = start < end ? end : start;
        final selectedText =
            value.text.substring(normalizedStart, normalizedEnd);
        unawaited(
          Clipboard.setData(
            ClipboardData(text: selectedText),
          ),
        );
      }
      return KeyEventResult.handled;
    }

    final isCut = (key == LogicalKeyboardKey.cut ||
            keyChar == 'x' ||
            key == LogicalKeyboardKey.keyX) &&
        hasModifier;
    if (isCut) {
      final value = _controller.value;
      final selection = value.selection;
      if (selection.isValid && !selection.isCollapsed) {
        final start = selection.start;
        final end = selection.end;
        final normalizedStart = start < end ? start : end;
        final normalizedEnd = start < end ? end : start;
        final selectedText =
            value.text.substring(normalizedStart, normalizedEnd);
        unawaited(
          Clipboard.setData(
            ClipboardData(text: selectedText),
          ),
        );
        final updatedText = value.text.replaceRange(
          normalizedStart,
          normalizedEnd,
          '',
        );
        _controller.value = value.copyWith(
          text: updatedText,
          selection: TextSelection.collapsed(offset: normalizedStart),
          composing: TextRange.empty,
        );
      }
      return KeyEventResult.handled;
    }

    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    if (event.repeat) {
      return KeyEventResult.handled;
    }

    if (isComposing) {
      return KeyEventResult.ignored;
    }

    if (shiftPressed) {
      final value = _controller.value;
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : value.text.length;
      final normalizedStart = start < end ? start : end;
      final normalizedEnd = start < end ? end : start;
      final updatedText = value.text.replaceRange(
        normalizedStart,
        normalizedEnd,
        '\n',
      );
      _controller.value = value.copyWith(
        text: updatedText,
        selection: TextSelection.collapsed(offset: normalizedStart + 1),
        composing: TextRange.empty,
      );
      return KeyEventResult.handled;
    }

    unawaited(_send());
    return KeyEventResult.handled;
  }
}
