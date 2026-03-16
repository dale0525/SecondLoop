import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/firebase_http_client_factory_stub.dart'
    if (dart.library.io) 'package:secondloop/core/cloud/firebase_http_client_factory_io.dart';

void main() {
  test('Firebase platform http client honors HttpOverrides on io', () async {
    var overrideUsed = false;
    final baseClient = HttpClient();

    try {
      await HttpOverrides.runZoned(() async {
        final client = createFirebasePlatformHttpClient();
        expect(overrideUsed, isTrue);
        client.close();
      }, createHttpClient: (SecurityContext? context) {
        overrideUsed = true;
        return baseClient;
      });
    } finally {
      baseClient.close(force: true);
    }
  });
}
