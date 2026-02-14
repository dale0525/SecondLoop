import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _isPhysicalFallbackLogicalKey(int keyId) =>
    keyId >= 0x01400000000 && keyId < 0x01500000000;

final class MacOsKeyEventChannelNormalizer {
  final Map<int, int> _pressedLogicalByKeyCode = <int, int>{};

  dynamic normalizeMessage(dynamic message) {
    if (message is! Map<Object?, Object?>) {
      return message;
    }

    final keymap = message['keymap'];
    if (keymap != 'macos') {
      return message;
    }

    final type = message['type'];
    final keyCode = _asInt(message['keyCode']);
    if (type == 'keydown') {
      if (keyCode != null) {
        final logical = _asInt(message['specifiedLogicalKey']);
        if (logical != null) {
          _pressedLogicalByKeyCode[keyCode] = logical;
        } else {
          _pressedLogicalByKeyCode.remove(keyCode);
        }
      }
      return message;
    }

    if (type != 'keyup' || keyCode == null) {
      return message;
    }

    final recordedLogical = _pressedLogicalByKeyCode.remove(keyCode);
    if (recordedLogical == null) {
      return message;
    }

    final currentLogical = _asInt(message['specifiedLogicalKey']);
    if (currentLogical == null || currentLogical == recordedLogical) {
      return message;
    }
    if (!_isPhysicalFallbackLogicalKey(currentLogical)) {
      return message;
    }

    final normalized = Map<Object?, Object?>.from(message);
    normalized['specifiedLogicalKey'] = recordedLogical;
    return normalized;
  }

  int? _asInt(Object? value) => value is int ? value : null;
}

final class MacOsKeyDataNormalizer {
  final Map<int, int> _pressedLogicalByPhysical = <int, int>{};

  ui.KeyData normalizeKeyData(ui.KeyData data) {
    switch (data.type) {
      case ui.KeyEventType.down:
      case ui.KeyEventType.repeat:
        _pressedLogicalByPhysical[data.physical] = data.logical;
        return data;
      case ui.KeyEventType.up:
        final recordedLogical = _pressedLogicalByPhysical.remove(data.physical);
        if (recordedLogical == null || recordedLogical == data.logical) {
          return data;
        }
        if (!_isPhysicalFallbackLogicalKey(data.logical)) {
          return data;
        }
        return ui.KeyData(
          timeStamp: data.timeStamp,
          type: data.type,
          physical: data.physical,
          logical: recordedLogical,
          character: data.character,
          synthesized: data.synthesized,
          deviceType: data.deviceType,
        );
    }
  }
}

bool _macOsKeyEventChannelNormalizerInstalled = false;

void installMacOsKeyEventChannelNormalizer() {
  if (_macOsKeyEventChannelNormalizerInstalled) {
    return;
  }
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
    return;
  }

  final servicesBinding = ServicesBinding.instance;
  final keyEventManager = servicesBinding.keyEventManager;
  final channelNormalizer = MacOsKeyEventChannelNormalizer();
  final keyDataNormalizer = MacOsKeyDataNormalizer();

  final originalOnKeyData = servicesBinding.platformDispatcher.onKeyData ??
      keyEventManager.handleKeyData;
  servicesBinding.platformDispatcher.onKeyData = (ui.KeyData data) {
    final normalizedData = keyDataNormalizer.normalizeKeyData(data);
    return originalOnKeyData(normalizedData);
  };

  SystemChannels.keyEvent.setMessageHandler((dynamic message) {
    final normalized = channelNormalizer.normalizeMessage(message);
    return keyEventManager.handleRawKeyMessage(normalized);
  });

  _macOsKeyEventChannelNormalizerInstalled = true;
}
