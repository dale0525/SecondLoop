import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'package:secondloop/features/media_backup/image_compression.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_image_compress');

  late FlutterImageCompressPlatform originalPlatform;

  setUp(() {
    originalPlatform = FlutterImageCompressPlatform.instance;
    FlutterImageCompressPlatform.instance = _TestImageCompressPlatform(channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    FlutterImageCompressPlatform.instance = originalPlatform;
  });

  test('compressImageForStorage downsizes landscape image to fit 1080p',
      () async {
    final bytes = _jpegBytes(width: 2500, height: 1000);

    List<dynamic>? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'compressWithList');
      args = call.arguments as List<dynamic>;
      return bytes;
    });

    await compressImageForStorage(bytes, mimeType: 'image/jpeg');

    expect(args, isNotNull);
    expect(args![1], 1920);
    expect(args![2], 768);
  });

  test('compressImageForStorage downsizes portrait image to fit 1080p',
      () async {
    final bytes = _jpegBytes(width: 1200, height: 1800);

    List<dynamic>? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'compressWithList');
      args = call.arguments as List<dynamic>;
      return bytes;
    });

    await compressImageForStorage(bytes, mimeType: 'image/jpeg');

    expect(args, isNotNull);
    expect(args![1], 1080);
    expect(args![2], 1620);
  });
}

Uint8List _jpegBytes({
  required int width,
  required int height,
}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodeJpg(image));
}

final class _TestImageCompressPlatform extends FlutterImageCompressPlatform {
  _TestImageCompressPlatform(this.channel)
      : _validator = FlutterImageCompressValidator(channel)
          ..ignoreCheckSupportPlatform = true;

  final MethodChannel channel;
  final FlutterImageCompressValidator _validator;

  @override
  FlutterImageCompressValidator get validator => _validator;

  @override
  Future<Uint8List> compressWithList(
    Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async {
    final result = await channel.invokeMethod<Uint8List>('compressWithList', [
      image,
      minWidth,
      minHeight,
      quality,
      rotate,
      autoCorrectionAngle,
      format.index,
      keepExif,
      inSampleSize,
    ]);
    return result ?? Uint8List(0);
  }

  @override
  void ignoreCheckSupportPlatform(bool bool) {
    _validator.ignoreCheckSupportPlatform = bool;
  }

  @override
  Future<void> showNativeLog(bool value) => throw UnimplementedError();

  @override
  Future<Uint8List?> compressWithFile(
    String path, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
    int numberOfRetries = 5,
  }) =>
      throw UnimplementedError();

  @override
  Future<XFile?> compressAndGetFile(
    String path,
    String targetPath, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
    int numberOfRetries = 5,
  }) =>
      throw UnimplementedError();

  @override
  Future<Uint8List?> compressAssetImage(
    String assetName, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) =>
      throw UnimplementedError();
}
