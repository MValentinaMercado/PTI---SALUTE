import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/core/active_profile_controller.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/components/profile_avatar.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// Selector global de "sobre quién estoy trabajando ahora" (BUG-006,
/// Parte 2). Es una píldora tocable que muestra el perfil activo
/// (`ActiveProfileController.instance.active`); al tocarla, deja elegir
/// entre los perfiles que el usuario ADMINISTRA: el propio y sus
/// dependientes (hijos, mascotas...).
///
/// A propósito no lista a los demás integrantes de la familia, aunque
/// compartan datos: las reglas de Firestore solo dejan escribir a quien
/// administra el perfil (`request.auth.uid == profile.uid`), así que
/// cargarles datos desde acá fallaría. A ellos se los ve (solo lectura,
/// con consentimiento) desde Familia.
///
/// Elegir acá actualiza `ActiveProfileController`; el Diario, la Agenda y
/// la tarjeta de medicación del Home leen ese valor.
class ActiveProfileSelector extends StatelessWidget {
  const ActiveProfileSelector({super.key});

  Future<void> _openPicker(BuildContext context) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final all = await ProfileService.instance.watchProfiles().first;
    // Solo lo que administro: mi perfil primero, después el resto por nombre.
    final profiles = all.where((p) => p.ownerUid == myUid).toList()
      ..sort((a, b) {
        if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    if (!context.mounted || profiles.isEmpty) return;
    final selected = await showModalBottomSheet<FamilyProfile>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProfileSwitcherSheet(profiles: profiles),
    );
    if (selected != null) {
      ActiveProfileController.instance.setActive(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ActiveProfileController.instance,
      builder: (context, _) {
        final active = ActiveProfileController.instance.active;
        final isPet = active?.type == ProfileType.mascota;
        return GestureDetector(
          onTap: () => _openPicker(context),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(DsBorderRadius.full),
              boxShadow: DsShadow.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active != null)
                  ProfileAvatar.fromProfile(active, radius: 14)
                else
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: isPet ? SaluteColors.terracotta : SaluteColors.darkGreen,
                    child: Icon(
                      isPet ? Icons.pets_outlined : Icons.person_outline,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  // Mientras carga el primer snapshot de Firestore
                  // (`active` todavía null), no mostramos "Elegir perfil":
                  // eso sugeriría que la app no sabe qué hacer, cuando en
                  // realidad ya sabemos que va a caer en el perfil propio
                  // apenas llegue el snapshot (ver ActiveProfileController.ensureValid).
                  active?.name ?? 'Cargando…',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: DsFontSize.md,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 18, color: Colors.grey[500]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileSwitcherSheet extends StatelessWidget {
  final List<FamilyProfile> profiles;
  const _ProfileSwitcherSheet({required this.profiles});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Sobre quién querés trabajar?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              'Podés cargar datos para vos y para tus dependientes.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ...profiles.map(
              (p) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ProfileAvatar.fromProfile(p, radius: 20),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(p.isSelf ? 'Vos' : (p.relation.isNotEmpty ? p.relation : (p.type == ProfileType.mascota ? 'Mascota' : 'Dependiente'))),
                trailing: ActiveProfileController.instance.activeProfileId == p.id
                    ? const Icon(Icons.check_circle, color: SaluteColors.primaryGreen)
                    : null,
                onTap: () => Navigator.of(context).pop(p),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
