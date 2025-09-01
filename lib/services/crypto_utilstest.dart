import 'dart:convert';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart' as basic;
import 'package:pointycastle/export.dart';

class MyCryptoUtils {
  /// Convert PEM public key to RSAPublicKey
  static RSAPublicKey rsaPublicKeyFromPem(String pem) {
    return basic.CryptoUtils.rsaPublicKeyFromPem(pem);
  }

  /// Convert PEM private key to RSAPrivateKey
  static RSAPrivateKey rsaPrivateKeyFromPem(String pem) {
    return basic.CryptoUtils.rsaPrivateKeyFromPem(pem);
  }

  /// Encrypts [plaintext] using RSA public key.
  /// Returns a Base64-encoded string.
  static String rsaEncrypt(String plaintext, RSAPublicKey publicKey) {
    try {
      // Use PKCS1 padding for RSA encryption
      final encryptor = OAEPEncoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

      final input = Uint8List.fromList(utf8.encode(plaintext));
      final encrypted = _processInBlocks(encryptor, input);

      return base64Encode(encrypted);
    } catch (e) {
      print('Error in rsaEncrypt: $e');
      // Try with basic RSA if OAEP fails
      final engine =
          RSAEngine()..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

      final input = Uint8List.fromList(utf8.encode(plaintext));
      final encrypted = _processInBlocks(engine, input);

      return base64Encode(encrypted);
    }
  }

  /// Decrypts a Base64-encoded string using RSA private key.
  /// Returns the original plaintext string.
  static String rsaDecrypt(String base64Ciphertext, RSAPrivateKey privateKey) {
    try {
      // First, try to decode the base64
      final encrypted = base64Decode(base64Ciphertext);

      // Try OAEP padding first
      try {
        final decryptor = OAEPEncoding(RSAEngine())
          ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

        final decrypted = _processInBlocks(decryptor, encrypted);
        return utf8.decode(decrypted, allowMalformed: true);
      } catch (e) {
        print('OAEP decryption failed, trying PKCS1: $e');
      }

      // Try PKCS1 padding
      try {
        final decryptor = PKCS1Encoding(RSAEngine())
          ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

        final decrypted = _processInBlocks(decryptor, encrypted);
        return utf8.decode(decrypted, allowMalformed: true);
      } catch (e) {
        print('PKCS1 decryption failed, trying raw RSA: $e');
      }

      // Fallback to raw RSA
      final engine =
          RSAEngine()
            ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

      final decrypted = _processInBlocks(engine, encrypted);

      // Try to decode as UTF-8, with fallback
      try {
        return utf8.decode(decrypted);
      } catch (e) {
        // If UTF-8 decode fails, try to clean the data
        return _cleanDecryptedData(decrypted);
      }
    } catch (e) {
      print('Fatal error in rsaDecrypt: $e');
      print('Input length: ${base64Ciphertext.length}');
      rethrow;
    }
  }

  /// Helper to handle RSA encryption/decryption in chunks
  static Uint8List _processInBlocks(dynamic engine, Uint8List input) {
    // Determine block size based on engine type
    int inputBlockSize;
    int outputBlockSize;

    if (engine is RSAEngine) {
      inputBlockSize = engine.inputBlockSize;
      outputBlockSize = engine.outputBlockSize;
    } else if (engine is PKCS1Encoding) {
      inputBlockSize = engine.inputBlockSize;
      outputBlockSize = engine.outputBlockSize;
    } else if (engine is OAEPEncoding) {
      inputBlockSize = engine.inputBlockSize;
      outputBlockSize = engine.outputBlockSize;
    } else {
      throw ArgumentError('Unsupported engine type');
    }

    if (input.isEmpty) {
      return Uint8List(0);
    }

    final output = <int>[];

    for (var offset = 0; offset < input.length; offset += inputBlockSize) {
      final chunkSize =
          (offset + inputBlockSize < input.length)
              ? inputBlockSize
              : input.length - offset;

      final chunk = input.sublist(offset, offset + chunkSize);

      try {
        final processed = engine.process(chunk);
        output.addAll(processed);
      } catch (e) {
        print('Error processing block at offset $offset: $e');
        // Try to continue with other blocks
        if (offset + inputBlockSize < input.length) {
          continue;
        }
        throw e;
      }
    }

    return Uint8List.fromList(output);
  }

  /// Clean decrypted data by removing padding and non-printable characters
  static String _cleanDecryptedData(Uint8List data) {
    // Remove PKCS padding if present
    if (data.isNotEmpty) {
      // Check for PKCS padding pattern
      final lastByte = data.last;
      if (lastByte > 0 && lastByte <= 16) {
        bool isPadding = true;
        for (int i = data.length - lastByte; i < data.length; i++) {
          if (data[i] != lastByte) {
            isPadding = false;
            break;
          }
        }
        if (isPadding) {
          data = data.sublist(0, data.length - lastByte);
        }
      }
    }

    // Remove null bytes and other non-printable characters from the beginning
    int start = 0;
    while (start < data.length && (data[start] == 0 || data[start] < 32)) {
      start++;
    }

    if (start >= data.length) {
      throw FormatException('No valid data after cleaning');
    }

    // Remove from the end as well
    int end = data.length - 1;
    while (end > start && (data[end] == 0 || data[end] < 32)) {
      end--;
    }

    final cleaned = data.sublist(start, end + 1);
    return utf8.decode(cleaned, allowMalformed: true);
  }

  /// Alternative decryption method that's more lenient with format
  static String? tryDecryptWithFallback(
    String encryptedData,
    RSAPrivateKey privateKey,
  ) {
    // Try different base64 decodings
    Uint8List? encrypted;

    // Standard base64
    try {
      encrypted = base64Decode(encryptedData);
    } catch (e) {
      print('Standard base64 decode failed: $e');
    }

    // Try base64url
    if (encrypted == null) {
      try {
        encrypted = base64Url.decode(encryptedData);
      } catch (e) {
        print('Base64url decode failed: $e');
      }
    }

    // Try with padding fixes
    if (encrypted == null) {
      try {
        String padded = encryptedData;
        while (padded.length % 4 != 0) {
          padded += '=';
        }
        encrypted = base64Decode(padded);
      } catch (e) {
        print('Padded base64 decode failed: $e');
        return null;
      }
    }

    if (encrypted == null) return null;

    // Now try to decrypt
    return rsaDecrypt(base64Encode(encrypted), privateKey);
  }
}
