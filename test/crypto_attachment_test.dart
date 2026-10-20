import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saluteapp/core/services/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage en memoria, para no depender del Keystore.
  final store = <String, String>{};
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        switch (call.method) {
          case 'read':
            return store[args['key']];
          case 'write':
            store[args['key'] as String] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(args['key']);
            return null;
          case 'containsKey':
            return store.containsKey(args['key']);
          default:
            return null;
        }
      },
    );
  });

  final plain = Uint8List.fromList(List.generate(5000, (i) => i % 251));

  test('cifra y descifra un archivo (ida y vuelta)', () async {
    final enc = await CryptoService.instance.encryptBytes(plain);
    expect(CryptoService.isEncryptedFile(enc), isTrue);
    expect(enc.length, plain.length + 4 + 12 + 16);
    expect(await CryptoService.instance.decryptBytes(enc), plain);
  });

  test('el contenido cifrado no contiene el original', () async {
    final enc = await CryptoService.instance.encryptBytes(plain);
    expect(enc.sublist(4 + 12, 4 + 12 + 64), isNot(plain.sublist(0, 64)));
  });

  test('un archivo sin cifrar (legado) no se detecta como cifrado', () {
    expect(CryptoService.isEncryptedFile(plain), isFalse);
    // Cabecera JPEG típica.
    expect(CryptoService.isEncryptedFile(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46])), isFalse);
  });

  test('un archivo alterado falla la autenticación', () async {
    final enc = await CryptoService.instance.encryptBytes(plain);
    enc[enc.length ~/ 2] ^= 0x01;
    expect(() => CryptoService.instance.decryptBytes(enc), throwsA(anything));
  });

  test('descifrar algo sin cabecera lanza FormatException', () {
    expect(() => CryptoService.instance.decryptBytes(plain), throwsFormatException);
  });
}
