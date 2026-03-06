part of 'chat_page.dart';

extension _ChatPageStateInputKeyHandler on _ChatPageState {
  // ignore: deprecated_member_use
  KeyEventResult _handleComposerOnKey(FocusNode node, RawKeyEvent event) {
    // ignore: deprecated_member_use
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
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
    final shortcut = resolveTextEditingShortcut(
      key: key,
      keyLabel: event.data.keyLabel,
      character: event.character,
      metaPressed: metaPressed,
      controlPressed: controlPressed,
      shiftPressed: shiftPressed,
      supportedShortcuts: const <TextEditingShortcut>{
        TextEditingShortcut.selectAll,
        TextEditingShortcut.copy,
        TextEditingShortcut.paste,
        TextEditingShortcut.cut,
      },
    );

    if (shortcut == TextEditingShortcut.paste) {
      unawaited(_pasteIntoChatInput());
      return KeyEventResult.handled;
    }

    if (shortcut == TextEditingShortcut.selectAll) {
      final textLength = _controller.value.text.length;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: textLength,
      );
      return KeyEventResult.handled;
    }

    if (shortcut == TextEditingShortcut.copy) {
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

    if (shortcut == TextEditingShortcut.cut) {
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
