import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

class AESHelper {
  final Key key;
  final IV iv;

  // Constructor that accepts hex strings and converts them properly
  AESHelper(String keyHex, String ivHex)
      : key = Key.fromBase16(keyHex),
        iv = IV.fromBase16(ivHex);

  // Alternative constructor that accepts bytes directly
  AESHelper.fromBytes(Uint8List keyBytes, Uint8List ivBytes)
      : key = Key(keyBytes),
        iv = IV(ivBytes);

  Uint8List encryptData(Uint8List data) {
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    return encrypted.bytes;
  }

  Uint8List decryptData(Uint8List encryptedData) {
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decryptBytes(Encrypted(encryptedData), iv: iv);
    return Uint8List.fromList(decrypted);
  }

  // Helper method to get key as hex string
  String get keyHex => key.base16;

  // Helper method to get IV as hex string
  String get ivHex => iv.base16;
}
