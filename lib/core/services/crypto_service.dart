import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cifrado de aplicación (end-to-end lógico) para los campos sensibles
/// de la historia clínica, antes de que salgan hacia Firestore.
///
/// Firebase cifra en tránsito y en reposo, pero eso protege contra un
/// atacante externo, no contra un acceso al proyecto de Firebase en sí.
/// Para diagnósticos, observaciones médicas y mensajes clínicos hace
/// falta una capa extra: se cifra en el dispositivo con AES-256-GCM y
/// la clave nunca sale del Keystore/Keychain del sistema operativo.
///
/// IMPORTANTE: esto es cifrado *de aplicación*, no cifrado extremo a
/// extremo real entre dispositivos (no hay un segundo participante con
/// su propia clave). Protege contra lectura directa de la base de datos,
/// no reemplaza un esquema E2E si en el futuro varios miembros de la
/// familia necesitan compartir y descifrar el mismo dato desde distintos
/// dispositivos; eso requeriría intercambio de claves (fuera de este
/// alcance por ahora).
class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  static const _keyStorageKey = 'salute_historial_key_v1';

  // BUG-008: "No se pudieron cargar las órdenes... PlatformException".
  // Pasaba porque flutter_secure_storage en Android guarda la clave
  // dentro de una EncryptedSharedPreferences respaldada por el Keystore
  // del sistema. Si esa clave del Keystore queda invalidada (reinstalar
  // la app restaurando un backup, cambiar el bloqueo de pantalla,
  // desenrolar/reenrolar huellas, etc.), CUALQUIER lectura tira una
  // PlatformException nativa en vez de devolver null — y como
  // _getOrCreateKey() se llama antes de descifrar cada orden, tira abajo
  // el fetch entero. `resetOnError: true` hace que el plugin, ante ese
  // caso, borre el storage corrupto y devuelva null en vez de explotar
  // (a costa de perder la clave vieja: los registros cifrados con ella
  // quedan indescifrables, pero al menos la app vuelve a andar en vez de
  // romperse por completo).
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );
  final _algorithm = AesGcm.with256bits();

  SecretKey? _cachedKey;

  /// Lectura/creación de la clave en curso. Sirve para que, si varias
  /// pantallas piden cifrar/descifrar al mismo tiempo cuando todavía no
  /// hay clave guardada (ej. primer arranque), TODAS esperen a la misma
  /// operación en vez de que cada una genere su propia clave distinta.
  ///
  /// Ese era el origen más probable de "SecretBox has wrong message
  /// authentication code (MAC)": dos llamadas concurrentes veían
  /// `stored == null`, cada una creaba una clave, la última en escribir
  /// pisaba a la otra, y todo lo cifrado con la clave "perdedora"
  /// quedaba indescifrable para siempre.
  Future<SecretKey>? _keyFuture;

  Future<SecretKey> _getOrCreateKey() async {
    final cached = _cachedKey;
    if (cached != null) return cached;

    final pending = _keyFuture ??= _loadOrCreateKey();
    try {
      return await pending;
    } catch (_) {
      // Si falló, permitimos reintentar en la próxima llamada.
      _keyFuture = null;
      rethrow;
    }
  }

  Future<SecretKey> _loadOrCreateKey() async {
    String? stored;
    try {
      stored = await _secureStorage.read(key: _keyStorageKey);
    } catch (e) {
      // No debería pasar más con resetOnError, pero por las dudas no
      // dejamos que una excepción nativa tire abajo toda la pantalla que
      // esté leyendo historial: tratamos "no pude leer la clave" igual
      // que "no había clave todavía" y generamos una nueva.
      debugPrint('CryptoService: fallo leyendo la clave, se genera una nueva. $e');
      stored = null;
    }

    if (stored != null) {
      try {
        final key = SecretKey(base64Decode(stored));
        _cachedKey = key;
        return key;
      } on FormatException catch (e) {
        debugPrint('CryptoService: la clave guardada está corrupta, se genera una nueva. $e');
      }
    }

    final newKey = await _algorithm.newSecretKey();
    final bytes = await newKey.extractBytes();
    await _secureStorage.write(key: _keyStorageKey, value: base64Encode(bytes));
    _cachedKey = newKey;
    return newKey;
  }

  /// Cifra un mapa (JSON) y devuelve un único string listo para
  /// guardar como campo `String` en Firestore.
  /// Formato: base64(nonce) + '.' + base64(ciphertext+mac)
  Future<String> encryptJson(Map<String, dynamic> data) async {
    final key = await _getOrCreateKey();
    final plaintext = utf8.encode(jsonEncode(data));
    final box = await _algorithm.encrypt(plaintext, secretKey: key);
    final nonceB64 = base64Encode(box.nonce);
    final payloadB64 = base64Encode(box.cipherText + box.mac.bytes);
    return '$nonceB64.$payloadB64';
  }

  /// Inverso de [encryptJson].
  Future<Map<String, dynamic>> decryptJson(String encoded) async {
    final key = await _getOrCreateKey();
    final parts = encoded.split('.');
    if (parts.length != 2) {
      throw const FormatException('Formato de dato cifrado inválido.');
    }
    final nonce = base64Decode(parts[0]);
    final payload = base64Decode(parts[1]);
    // El mac de AES-GCM-256 son los últimos 16 bytes.
    final cipherText = payload.sublist(0, payload.length - 16);
    final mac = Mac(payload.sublist(payload.length - 16));

    final box = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plaintext = await _algorithm.decrypt(box, secretKey: key);
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }

  // ── Archivos (adjuntos) ────────────────────────────────────────────────
  //
  // Mismo AES-256-GCM y misma clave que los detalles del historial.
  // Formato del archivo: "SLT1" (4 bytes, identifica un adjunto cifrado y
  // deja distinguir los archivos viejos sin cifrar) + nonce (12) +
  // texto cifrado + MAC (16).

  static const List<int> _fileMagic = [0x53, 0x4C, 0x54, 0x31]; // "SLT1"

  /// ¿Estos bytes son un adjunto ya cifrado con [encryptBytes]?
  static bool isEncryptedFile(List<int> bytes) {
    if (bytes.length < _fileMagic.length + 12 + 16) return false;
    for (var i = 0; i < _fileMagic.length; i++) {
      if (bytes[i] != _fileMagic[i]) return false;
    }
    return true;
  }

  Future<Uint8List> encryptBytes(List<int> plain) async {
    final key = await _getOrCreateKey();
    final box = await _algorithm.encrypt(plain, secretKey: key);
    final body = box.concatenation(); // nonce + cifrado + mac
    final out = Uint8List(_fileMagic.length + body.length);
    out.setRange(0, _fileMagic.length, _fileMagic);
    out.setRange(_fileMagic.length, out.length, body);
    return out;
  }

  /// Inverso de [encryptBytes]. Lanza si los bytes no son un adjunto
  /// cifrado o si la clave no coincide (MAC inválido).
  Future<Uint8List> decryptBytes(List<int> encrypted) async {
    if (!isEncryptedFile(encrypted)) {
      throw const FormatException('El archivo no está cifrado con el formato esperado.');
    }
    final key = await _getOrCreateKey();
    final box = SecretBox.fromConcatenation(
      encrypted.sublist(_fileMagic.length),
      nonceLength: _algorithm.nonceLength,
      macLength: 16,
    );
    final plain = await _algorithm.decrypt(box, secretKey: key);
    return Uint8List.fromList(plain);
  }
}
