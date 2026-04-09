import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

const int _kValueNull = 0;
const int _kValueTrue = 1;
const int _kValueFalse = 2;
const int _kValueInt32 = 3;
const int _kValueInt64 = 4;
const int _kValueLargeInt = 5;
const int _kValueFloat64 = 6;
const int _kValueString = 7;
const int _kValueList = 12;
const int _kValueMap = 13;

class StandardMessageCodecCompat {
  const StandardMessageCodecCompat();

  ByteData? encodeMessage(Object? message) {
    if (message == null) {
      return null;
    }
    final buffer = _WriteBuffer(startCapacity: 64);
    _writeValue(buffer, message);
    return buffer.done();
  }

  Object? decodeMessage(ByteData? message) {
    if (message == null) {
      return null;
    }
    final buffer = _ReadBuffer(message);
    final result = _readValue(buffer);
    if (buffer.hasRemaining) {
      throw const FormatException('Message corrupted');
    }
    return result;
  }

  void _writeValue(_WriteBuffer buffer, Object? value) {
    if (value == null) {
      buffer.putUint8(_kValueNull);
    } else if (value is bool) {
      buffer.putUint8(value ? _kValueTrue : _kValueFalse);
    } else if (value is double) {
      buffer.putUint8(_kValueFloat64);
      buffer.putFloat64(value);
    } else if (value is int) {
      if (-0x7fffffff - 1 <= value && value <= 0x7fffffff) {
        buffer.putUint8(_kValueInt32);
        buffer.putInt32(value);
      } else {
        buffer.putUint8(_kValueInt64);
        buffer.putInt64(value);
      }
    } else if (value is String) {
      buffer.putUint8(_kValueString);
      final bytes = utf8.encode(value);
      _writeSize(buffer, bytes.length);
      buffer.putUint8List(Uint8List.fromList(bytes));
    } else if (value is List) {
      buffer.putUint8(_kValueList);
      _writeSize(buffer, value.length);
      for (final item in value) {
        _writeValue(buffer, item);
      }
    } else if (value is Map) {
      buffer.putUint8(_kValueMap);
      _writeSize(buffer, value.length);
      value.forEach((key, entryValue) {
        _writeValue(buffer, key);
        _writeValue(buffer, entryValue);
      });
    } else {
      throw ArgumentError.value(value, 'value', 'Unsupported message value');
    }
  }

  Object? _readValue(_ReadBuffer buffer) {
    if (!buffer.hasRemaining) {
      throw const FormatException('Message corrupted');
    }
    return _readValueOfType(buffer.getUint8(), buffer);
  }

  Object? _readValueOfType(int type, _ReadBuffer buffer) {
    switch (type) {
      case _kValueNull:
        return null;
      case _kValueTrue:
        return true;
      case _kValueFalse:
        return false;
      case _kValueInt32:
        return buffer.getInt32();
      case _kValueInt64:
        return buffer.getInt64();
      case _kValueLargeInt:
      case _kValueString:
        final length = _readSize(buffer);
        return utf8.decode(buffer.getUint8List(length));
      case _kValueFloat64:
        return buffer.getFloat64();
      case _kValueList:
        final length = _readSize(buffer);
        return List<Object?>.generate(length, (_) => _readValue(buffer));
      case _kValueMap:
        final length = _readSize(buffer);
        final result = <Object?, Object?>{};
        for (var index = 0; index < length; index += 1) {
          result[_readValue(buffer)] = _readValue(buffer);
        }
        return result;
      default:
        throw FormatException('Unsupported StandardMessageCodec type: $type');
    }
  }

  void _writeSize(_WriteBuffer buffer, int value) {
    if (value < 254) {
      buffer.putUint8(value);
    } else if (value <= 0xffff) {
      buffer.putUint8(254);
      buffer.putUint16(value);
    } else {
      buffer.putUint8(255);
      buffer.putUint32(value);
    }
  }

  int _readSize(_ReadBuffer buffer) {
    final value = buffer.getUint8();
    switch (value) {
      case 254:
        return buffer.getUint16();
      case 255:
        return buffer.getUint32();
      default:
        return value;
    }
  }
}

class _WriteBuffer {
  factory _WriteBuffer({int startCapacity = 8}) {
    final scratch = ByteData(8);
    return _WriteBuffer._(
      Uint8List(startCapacity),
      scratch,
      scratch.buffer.asUint8List(),
    );
  }

  _WriteBuffer._(this._buffer, this._scratch, this._scratchList);

  Uint8List _buffer;
  int _currentSize = 0;
  bool _isDone = false;
  final ByteData _scratch;
  final Uint8List _scratchList;
  static final Uint8List _zeroBuffer = Uint8List(8);

  void putUint8(int byte) {
    _ensureNotDone();
    _writeByte(byte);
  }

  void putUint16(int value) {
    _ensureNotDone();
    _scratch.setUint16(0, value, Endian.host);
    _append(_scratch.buffer.asUint8List(0, 2));
  }

  void putUint32(int value) {
    _ensureNotDone();
    _scratch.setUint32(0, value, Endian.host);
    _append(_scratch.buffer.asUint8List(0, 4));
  }

  void putInt32(int value) {
    _ensureNotDone();
    _scratch.setInt32(0, value, Endian.host);
    _append(_scratch.buffer.asUint8List(0, 4));
  }

  void putInt64(int value) {
    _ensureNotDone();
    _scratch.setInt64(0, value, Endian.host);
    _append(_scratch.buffer.asUint8List(0, 8));
  }

  void putFloat64(double value) {
    _ensureNotDone();
    _alignTo(8);
    _scratch.setFloat64(0, value, Endian.host);
    _append(_scratchList);
  }

  void putUint8List(Uint8List value) {
    _ensureNotDone();
    _append(value);
  }

  ByteData done() {
    if (_isDone) {
      throw StateError('done() must not be called more than once.');
    }
    final result = _buffer.buffer.asByteData(0, _currentSize);
    _buffer = Uint8List(0);
    _isDone = true;
    return result;
  }

  void _ensureNotDone() {
    if (_isDone) {
      throw StateError('Cannot write after done().');
    }
  }

  void _writeByte(int byte) {
    if (_currentSize == _buffer.length) {
      _resize();
    }
    _buffer[_currentSize] = byte;
    _currentSize += 1;
  }

  void _append(Uint8List bytes) {
    final newSize = _currentSize + bytes.length;
    if (newSize > _buffer.length) {
      _resize(newSize);
    }
    _buffer.setRange(_currentSize, newSize, bytes);
    _currentSize = newSize;
  }

  void _resize([int? requiredLength]) {
    final newLength = math.max(requiredLength ?? 0, _buffer.length * 2);
    final newBuffer = Uint8List(newLength);
    newBuffer.setRange(0, _buffer.length, _buffer);
    _buffer = newBuffer;
  }

  void _alignTo(int alignment) {
    final mod = _currentSize % alignment;
    if (mod != 0) {
      _append(_zeroBuffer.sublist(0, alignment - mod));
    }
  }
}

class _ReadBuffer {
  _ReadBuffer(this.data);

  final ByteData data;
  int _position = 0;

  bool get hasRemaining => _position < data.lengthInBytes;

  int getUint8() {
    return data.getUint8(_position++);
  }

  int getUint16() {
    final value = data.getUint16(_position, Endian.host);
    _position += 2;
    return value;
  }

  int getUint32() {
    final value = data.getUint32(_position, Endian.host);
    _position += 4;
    return value;
  }

  int getInt32() {
    final value = data.getInt32(_position, Endian.host);
    _position += 4;
    return value;
  }

  int getInt64() {
    final value = data.getInt64(_position, Endian.host);
    _position += 8;
    return value;
  }

  double getFloat64() {
    _alignTo(8);
    final value = data.getFloat64(_position, Endian.host);
    _position += 8;
    return value;
  }

  Uint8List getUint8List(int length) {
    final result =
        data.buffer.asUint8List(data.offsetInBytes + _position, length);
    _position += length;
    return result;
  }

  void _alignTo(int alignment) {
    final mod = _position % alignment;
    if (mod != 0) {
      _position += alignment - mod;
    }
  }
}
