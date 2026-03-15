import 'dart:io';

Object createPlatformHttpClient() =>
    HttpOverrides.current?.createHttpClient(null) ?? HttpClient();
