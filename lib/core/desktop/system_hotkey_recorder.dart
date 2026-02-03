// ignore_for_file: deprecated_member_use

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

final class SystemHotKeyRecorder extends StatefulWidget {
  const SystemHotKeyRecorder({
    super.key,
    required this.initialHotKey,
    required this.onHotKeyRecorded,
  });

  final HotKey initialHotKey;
  final ValueChanged<HotKey> onHotKeyRecorded;

  @override
  State<SystemHotKeyRecorder> createState() => _SystemHotKeyRecorderState();
}

class _SystemHotKeyRecorderState extends State<SystemHotKeyRecorder> {
  @override
  void initState() {
    super.initState();
    RawKeyboard.instance.addListener(_handleRawKeyEvent);
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(_handleRawKeyEvent);
    super.dispose();
  }

  void _handleRawKeyEvent(RawKeyEvent event) {
    if (event is RawKeyUpEvent) return;

    final key = event.physicalKey;
    if (_isModifierKey(key)) return;

    final modifiers = <HotKeyModifier>[
      if (event.isAltPressed) HotKeyModifier.alt,
      if (event.isControlPressed) HotKeyModifier.control,
      if (event.isMetaPressed) HotKeyModifier.meta,
      if (event.isShiftPressed) HotKeyModifier.shift,
    ];

    widget.onHotKeyRecorded(
      HotKey(
        identifier: widget.initialHotKey.identifier,
        key: key,
        modifiers: modifiers.isEmpty ? null : modifiers,
        scope: widget.initialHotKey.scope,
      ),
    );
  }

  bool _isModifierKey(PhysicalKeyboardKey key) {
    return key == PhysicalKeyboardKey.shiftLeft ||
        key == PhysicalKeyboardKey.shiftRight ||
        key == PhysicalKeyboardKey.controlLeft ||
        key == PhysicalKeyboardKey.controlRight ||
        key == PhysicalKeyboardKey.altLeft ||
        key == PhysicalKeyboardKey.altRight ||
        key == PhysicalKeyboardKey.metaLeft ||
        key == PhysicalKeyboardKey.metaRight ||
        key == PhysicalKeyboardKey.capsLock ||
        key == PhysicalKeyboardKey.fn;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
