import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../src/rust/semantic_parse.dart';

abstract interface class SemanticParseEnhancementBackend {
  Future<String> semanticParseMessageActionEnhancement(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required String localResultJson,
    required List<String> unresolvedFields,
    required List<TodoCandidate> candidates,
  });

  Future<String> semanticParseMessageActionEnhancementCloudGateway(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required String localResultJson,
    required List<String> unresolvedFields,
    required List<TodoCandidate> candidates,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  });
}
