import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createPlatformHttpClient() =>
    IOClient(HttpOverrides.current?.createHttpClient(null) ?? HttpClient());
