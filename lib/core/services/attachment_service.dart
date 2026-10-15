import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

    final root = await _root();
    final dest = File('${root.path}/$relative');
    await dest.parent.create(recursive: true);
    await source.copy(dest.path);

    return OrderAttachment(
      path: relative,
      name: originalName,
      type: _isPdfName(originalName) ? 'pdf' : 'image',
    );
  }

  bool _isPdfName(String name) => name.toLowerCase().endsWith('.pdf');

  // ── Lectura ──────────────────────────────────────────────────────────────

  /// Convierte la ruta relativa en un File. Null si ya no existe
  /// (ej: la orden se creó en otro dispositivo).
  Future<File?> resolve(String relativePath) async {
    final root = await _root();
    final file = File('${root.path}/$relativePath');
    return await file.exists() ? file : null;
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
      final file = await resolve(relativePath);
      await file?.delete();
    } catch (e) {
      debugPrint('AttachmentService: no se pudo borrar $relativePath. $e');
    }
  }
}