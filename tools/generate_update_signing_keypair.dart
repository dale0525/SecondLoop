import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final keyData = await keyPair.extract();
  final publicKey = await keyPair.extractPublicKey();

  stdout.writeln(jsonEncode(<String, String>{
    'private_key_base64': base64Encode(keyData.bytes),
    'public_key_base64': base64Encode(publicKey.bytes),
  }));
}
