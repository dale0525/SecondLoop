import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:secondloop/core/update/android/android_apk_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelAndroidApkInstaller', () {
    const channelName = 'secondloop/android_update';

    late MethodChannel channel;
    final calls = <MethodCall>[];

    setUp(() {
      channel = const MethodChannel(channelName);
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return <String, Object?>{'status': 'permission_settings_opened'};
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps permission settings handoff to dedicated exception', () async {
      final installer = MethodChannelAndroidApkInstaller(channel: channel);

      await expectLater(
        () => installer.installApk(apkPath: '/tmp/secondloop.apk'),
        throwsA(isA<AndroidApkInstallerRequiresPermissionSettingsException>()),
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'installApk');
      expect(calls.single.arguments,
          <String, Object?>{'path': '/tmp/secondloop.apk'});
    });

    test('rejects unknown install status payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel,
              (call) async => <String, Object?>{'status': 'unexpected'});
      final installer = MethodChannelAndroidApkInstaller(channel: channel);

      await expectLater(
        () => installer.installApk(apkPath: '/tmp/secondloop.apk'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('HttpAndroidApkDownloader cancellation', () {
    late Directory tempDir;
    late PathProviderPlatform oldPathProviderPlatform;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('android_apk_downloader_test_');
      oldPathProviderPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = oldPathProviderPlatform;
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('cancels before response body starts streaming', () async {
      final request = _FakeHttpClientRequest();
      final httpClient = _FakeHttpClient(request: request);
      final downloader = HttpAndroidApkDownloader(httpClient: httpClient);
      addTearDown(() async {
        await downloader.dispose();
      });
      final cancelToken = AndroidApkDownloadCancelToken();

      final future = downloader.downloadApk(
        downloadUri: Uri.parse('https://cdn.example.com/app.apk'),
        fileName: 'SecondLoop-android-arm64-v8a.apk',
        onProgress: (_) {},
        cancelToken: cancelToken,
      );

      await request.closeStarted.future;
      cancelToken.cancel();

      await expectLater(
          future, throwsA(isA<AndroidApkDownloadCancelledException>()));
      expect(httpClient.closeCalls, greaterThanOrEqualTo(1));
    });
  });
}

final class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({required this.request});

  final _FakeHttpClientRequest request;
  int closeCalls = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => request;

  @override
  void close({bool force = false}) {
    closeCalls += 1;
    request.completeWithAbort();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientRequest implements HttpClientRequest {
  final Completer<void> closeStarted = Completer<void>();
  final Completer<HttpClientResponse> responseCompleter =
      Completer<HttpClientResponse>();

  void completeWithAbort() {
    if (!responseCompleter.isCompleted) {
      responseCompleter.complete(_FakeHttpClientResponse.aborted());
    }
  }

  @override
  Future<HttpClientResponse> close() {
    if (!closeStarted.isCompleted) {
      closeStarted.complete();
    }
    return responseCompleter.future;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    completeWithAbort();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._stream,
      {required this.statusCode, required this.contentLength});

  factory _FakeHttpClientResponse.aborted() =>
      _FakeHttpClientResponse(const Stream<List<int>>.empty(),
          statusCode: HttpStatus.ok, contentLength: 0);

  final Stream<List<int>> _stream;

  @override
  final int statusCode;

  @override
  final int contentLength;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
