import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createFirebasePlatformHttpClient() {
  final inner = HttpOverrides.current?.createHttpClient(null) ?? HttpClient();
  return IOClient(inner);
}
