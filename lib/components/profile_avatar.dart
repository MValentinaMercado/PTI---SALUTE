import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';

/// Qué eligió el usuario en la hoja "Foto de perfil".
enum AvatarSource { camera, gallery, remove }

/// Foto de perfil ya procesada para guardar en Firestore.
///
/// La imagen se achica (máx. 480 px, JPEG calidad 70 → ~25-50 KB) y se guarda
/// como `data:image/jpeg;base64,...` en el mismo campo `avatarUrl` que ya
/// existía. Así no hace falta Firebase Storage, funciona con las reglas
/// actuales y la foto se sincroniza con toda la familia (a diferencia de los
/// adjuntos de órdenes, que quedan solo en el equipo).
///
/// `avatarUrl` sigue aceptando una URL http(s) normal (ej. la foto de Google).
class AvatarPhoto {
  AvatarPhoto._();

  static final _picker = ImagePicker();

  /// Muestra la hoja de opciones y devuelve:
  /// - `null`  → el usuario canceló (no cambiar nada),
  /// - `''`    → quitar la foto,
  /// - `data:` → foto nueva lista para guardar.
  static Future<String?> choose(BuildContext context, {required bool hasPhoto}) async {
    final source = await showModalBottomSheet<AvatarSource>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AvatarSourceSheet(hasPhoto: hasPhoto),
    );
    if (source == null) return null;
    if (source == AvatarSource.remove) return '';
    if (!context.mounted) return null;

    try {
      final x = await _picker.pickImage(
        source: source == AvatarSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 480,
        maxHeight: 480,
        imageQuality: 70,
        preferredCameraDevice: CameraDevice.front,
      );
      if (x == null) return null;
      final bytes = await x.readAsBytes();
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    } catch (e) {
      debugPrint('AvatarPhoto: no se pudo obtener la foto. $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == AvatarSource.camera
                  ? 'No se pudo abrir la cámara. Revisá los permisos de la app.'
                  : 'No se pudo abrir la galería. Revisá los permisos de la app.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return null;
    }
  }
}

class _AvatarSourceSheet extends StatelessWidget {
  final bool hasPhoto;
  const _AvatarSourceSheet({required this.hasPhoto});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Foto de perfil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            _SheetOption(
              icon: Icons.photo_camera_outlined,
              label: 'Sacar una foto',
              onTap: () => Navigator.pop(context, AvatarSource.camera),
            ),
            _SheetOption(
              icon: Icons.photo_library_outlined,
              label: 'Elegir de la galería',
              onTap: () => Navigator.pop(context, AvatarSource.gallery),
            ),
            if (hasPhoto)
              _SheetOption(
                icon: Icons.delete_outline,
                label: 'Quitar foto',
                color: const Color(0xFFB03A3A),
                onTap: () => Navigator.pop(context, AvatarSource.remove),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = SaluteColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color == SaluteColors.primaryGreen ? Colors.black87 : color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convierte el valor de `avatarUrl` en una imagen: `data:` (foto cargada
/// desde la app) o URL http(s). Devuelve null si está vacío o es inválido.
ImageProvider? avatarImageProvider(String avatarUrl) {
  final value = avatarUrl.trim();
  if (value.isEmpty) return null;
  if (value.startsWith('data:')) {
    final comma = value.indexOf(',');
    if (comma == -1) return null;
    try {
      final Uint8List bytes = base64Decode(value.substring(comma + 1));
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
  return NetworkImage(value);
}

/// Avatar de un perfil: foto si tiene; si no, ícono de persona/mascota o la
/// inicial. Con [onEditPhoto] muestra una insignia de cámara y la foto se
/// puede tocar para cambiarla.
class ProfileAvatar extends StatelessWidget {
  final String avatarUrl;
  final ProfileType type;
  final String name;
  final double radius;
  final VoidCallback? onEditPhoto;

  /// Borde blanco semitransparente (para usarlo sobre fondos de color).
  final bool ring;

  /// Muestra la inicial del nombre en vez del ícono cuando no hay foto.
  final bool showInitial;

  const ProfileAvatar({
    super.key,
    required this.avatarUrl,
    required this.type,
    this.name = '',
    this.radius = 24,
    this.onEditPhoto,
    this.ring = false,
    this.showInitial = false,
  });

  /// Atajo desde un [FamilyProfile].
  ProfileAvatar.fromProfile(
    FamilyProfile p, {
    super.key,
    this.radius = 24,
    this.onEditPhoto,
    this.ring = false,
    this.showInitial = false,
  })  : avatarUrl = p.avatarUrl,
        type = p.type,
        name = p.name;

  @override
  Widget build(BuildContext context) {
    final isPet = type == ProfileType.mascota;
    final image = avatarImageProvider(avatarUrl);
    final bg = isPet ? SaluteColors.terracotta : SaluteColors.darkGreen;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: image != null ? SaluteColors.lightGreen : bg,
      backgroundImage: image,
      onBackgroundImageError: image != null ? (_, __) {} : null,
      child: image != null
          ? null
          : (showInitial && name.trim().isNotEmpty
              ? Text(
                  name.trim().substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: radius * 0.85,
                  ),
                )
              : Icon(
                  isPet ? Icons.pets_outlined : Icons.person_outline,
                  color: Colors.white,
                  size: radius * 0.95,
                )),
    );

    if (ring) {
      avatar = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 2),
        ),
        child: avatar,
      );
    }

    if (onEditPhoto == null) return avatar;

    final badgeSize = (radius * 0.62).clamp(22.0, 34.0);
    return Semantics(
      button: true,
      label: 'Cambiar foto de perfil',
      child: GestureDetector(
        onTap: onEditPhoto,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: ring ? 2 : -2,
              bottom: ring ? 2 : -2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: SaluteColors.brownOrange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(Icons.photo_camera, color: Colors.white, size: badgeSize * 0.52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
