import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saluteapp/core/services/crypto_service.dart';

/// Archivo adjunto a una orden. Se guarda dentro de `details`
/// (que ya se cifra en MedicalRecordService).
///
/// IMPORTANTE: `path` es RELATIVO a la carpeta de documentos de la app
/// (ej: `ordenes/abc123/1735000000000_receta.jpg`). No se guarda la ruta
/// absoluta porque en iOS (y a veces en Android) cambia entre
/// actualizaciones o reinstalaciones. Se resuelve con
/// [AttachmentService.resolve].
class OrderAttachment {
  final String path;
  final String name;

  /// 'image' o 'pdf'
  final String type;

  const OrderAttachment({required this.path, required this.name, required this.type});

  bool get isImage => type == 'image';
  bool get isPdf => type == 'pdf';

  Map<String, dynamic> toDetails() => {
    'attachmentPath': path,
    'attachmentName': name,
    'attachmentType': type,
  };

  /// Devuelve null si la orden no tiene adjunto.
  static OrderAttachment? fromDetails(Map<String, dynamic> details) {
    final path = details['attachmentPath'];
    if (path is! String || path.isEmpty) return null;
    return OrderAttachment(
      path: path,
      name: (details['attachmentName'] as String?) ?? path.split('/').last,
      type: (details['attachmentType'] as String?) ?? 'image',
    );
  }
}

/// Guarda archivos de órdenes (foto o PDF) en el almacenamiento PRIVADO
/// de la app. Gratis, funciona offline y no requiere Firebase Storage.
///
/// CIFRADO: los archivos se guardan cifrados (AES-256-GCM, la misma clave
/// del Keystore/Keychain que usa el historial; ver `CryptoService`). En
/// disco nunca queda el contenido legible. Para mostrarlos:
///  - [readBytes] descifra en memoria (miniaturas).
///  - [resolve] / [open] / [share] descifran a una copia TEMPORAL en la
///    caché de la app, porque el visor del sistema, el OCR y el menú de
///    compartir necesitan un archivo real. Esa copia se borra al abrir y
///    cerrar la app ([clearTempFiles]) y al borrar el adjunto.
/// Los archivos viejos (sin cifrar) se detectan por su cabecera y se
/// cifran una vez con [migrateLegacyFiles]; mientras tanto se leen igual.
///
/// Limitación: los archivos viven solo en este dispositivo (no se
/// sincronizan con otros familiares y se pierden si se desinstala la app).
class AttachmentService {
  AttachmentService._();
  static final AttachmentService instance = AttachmentService._();

  final _picker = ImagePicker();

  // ── Selección ────────────────────────────────────────────────────────────

  /// Devuelve la ruta temporal de la foto, o null si el usuario cancela.
  Future<String?> pickFromCamera() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2200,
      imageQuality: 85,
    );
    return x?.path;
  }

  Future<String?> pickFromGallery() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2200,
      imageQuality: 85,
    );
    return x?.path;
  }

  /// Selector de archivos del sistema (PDF o imagen).
  Future<String?> pickDocument() {
    return FlutterFileDialog.pickFile(
      params: const OpenFileDialogParams(
        dialogType: OpenFileDialogType.document,
        // Android:
        mimeTypesFilter: ['application/pdf', 'image/jpeg', 'image/png'],
        // iOS:
        fileExtensionsFilter: ['pdf', 'jpg', 'jpeg', 'png'],
        copyFileToCacheDir: true,
      ),
    );
  }

  // ── Guardado ─────────────────────────────────────────────────────────────

  Future<Directory> _root() => getApplicationDocumentsDirectory();

  /// Copia [sourcePath] a `ordenes/{profileId}/` dentro de la carpeta
  /// privada de la app y devuelve el adjunto listo para guardar en `details`.
  Future<OrderAttachment> saveToPrivateStorage({
    required String profileId,
    required String sourcePath,
    String folder = 'ordenes',
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('El archivo seleccionado ya no existe.');
    }

    final originalName = sourcePath.split(RegExp(r'[\\/]')).last;
    final safeName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final relative = '$folder/$profileId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    // Se cifra ANTES de escribir: el archivo legible nunca toca la carpeta
    // de documentos de la app.
    final encrypted = await CryptoService.instance.encryptBytes(await source.readAsBytes());
    final root = await _root();
    final dest = File('${root.path}/$relative');
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(encrypted, flush: true);

    // La copia original (caché del selector / cámara) quedaba en claro.
    await _deleteIfTemp(source);

    return OrderAttachment(
      path: relative,
      name: originalName,
      type: _isPdfName(originalName) ? 'pdf' : 'image',
    );
  }

  bool _isPdfName(String name) => name.toLowerCase().endsWith('.pdf');

  // ── Lectura ──────────────────────────────────────────────────────────────

  /// Contenido descifrado en memoria. Null si el archivo no existe o no se
  /// pudo descifrar (clave perdida). Acepta archivos viejos sin cifrar.
  Future<Uint8List?> readBytes(String relativePath) async {
    try {
      final root = await _root();
      final file = File('${root.path}/$relativePath');
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (!CryptoService.isEncryptedFile(bytes)) return bytes; // legado
      return await CryptoService.instance.decryptBytes(bytes);
    } catch (e) {
      debugPrint('AttachmentService: no se pudo leer $relativePath. $e');
      return null;
    }
  }

  /// Copia temporal DESCIFRADA del adjunto (para OCR, visor y compartir).
  /// Null si ya no existe o no se pudo descifrar. No la guardes: se borra
  /// sola (ver [clearTempFiles]).
  Future<File?> resolve(String relativePath) async {
    final root = await _root();
    final stored = File('${root.path}/$relativePath');
    if (!await stored.exists()) return null;

    final tmp = await _tempFile(relativePath);
    // Reusa la copia si es más nueva que el original.
    if (await tmp.exists() && (await tmp.lastModified()).isAfter(await stored.lastModified())) {
      return tmp;
    }
    final plain = await readBytes(relativePath);
    if (plain == null) return null;
    await tmp.parent.create(recursive: true);
    await tmp.writeAsBytes(plain, flush: true);
    return tmp;
  }

  /// Abre el adjunto con el visor del sistema. Devuelve false si no se pudo.
  Future<bool> open(OrderAttachment attachment) async {
    final file = await resolve(attachment.path);
    if (file == null) return false;
    final result = await OpenFilex.open(file.path);
    return result.type == ResultType.done;
  }

  /// Comparte el adjunto (WhatsApp, mail, etc.). False si no está en el equipo.
  Future<bool> share(OrderAttachment attachment, {String? text}) async {
    final file = await resolve(attachment.path);
    if (file == null) return false;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text),
    );
    return true;
  }

  // ── Borrado ──────────────────────────────────────────────────────────────

  /// Borra el archivo. Llamalo al quitar el adjunto, al cancelar un
  /// formulario sin guardar y al eliminar una orden.
  Future<void> delete(String relativePath) async {
    try {
      final root = await _root();
      final stored = File('${root.path}/$relativePath');
      if (await stored.exists()) await stored.delete();
      final tmp = await _tempFile(relativePath);
      if (await tmp.exists()) await tmp.delete();
    } catch (e) {
      debugPrint('AttachmentService: no se pudo borrar $relativePath. $e');
    }
  }

  // ── Temporales y migración ───────────────────────────────────────────────

  static const _tempFolder = 'salute_attachments';
  static const _migratedKey = 'attachments_encrypted_v1';
  static const _folders = ['ordenes', 'vacunas'];

  Future<File> _tempFile(String relativePath) async {
    final tmp = await getTemporaryDirectory();
    return File('${tmp.path}/$_tempFolder/$relativePath');
  }

  /// Borra las copias descifradas. Llamalo al abrir la app, al cerrar
  /// sesión y al borrar la cuenta.
  Future<void> clearTempFiles() async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/$_tempFolder');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('AttachmentService: no se pudieron limpiar los temporales. $e');
    }
  }

  Future<void> _deleteIfTemp(File source) async {
    try {
      final tmp = await getTemporaryDirectory();
      if (source.path.startsWith(tmp.path)) await source.delete();
    } catch (_) {
      // Si no se puede borrar, queda en la caché del sistema: no es crítico.
    }
  }

  /// Cifra, una sola vez, los adjuntos guardados antes de este cambio.
  /// Idempotente (salta lo ya cifrado) y atómico por archivo (escribe a un
  /// `.tmp` y renombra). Las rutas NO cambian, así que no hay que tocar
  /// Firestore. Si algún archivo falla, no marca la migración como hecha y
  /// se reintenta en el próximo arranque. Devuelve cuántos cifró.
  Future<int> migrateLegacyFiles() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) ?? false) return 0;

    final root = await _root();
    var migrated = 0;
    var failures = 0;
    for (final folder in _folders) {
      final dir = Directory('${root.path}/$folder');
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File || entity.path.endsWith('.tmp')) continue;
        try {
          final bytes = await entity.readAsBytes();
          if (CryptoService.isEncryptedFile(bytes)) continue;
          final encrypted = await CryptoService.instance.encryptBytes(bytes);
          final tmp = File('${entity.path}.tmp');
          await tmp.writeAsBytes(encrypted, flush: true);
          await tmp.rename(entity.path);
          migrated++;
        } catch (e) {
          failures++;
          debugPrint('AttachmentService: no se pudo cifrar ${entity.path}. $e');
        }
      }
    }
    if (failures == 0) await prefs.setBool(_migratedKey, true);
    return migrated;
  }
}
