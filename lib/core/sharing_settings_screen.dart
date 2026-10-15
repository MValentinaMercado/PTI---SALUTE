import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// Configuración > Compartir perfiles.
///
/// Para cada perfil que administrás (el tuyo, tus dependientes y tus
/// mascotas) elegís con qué integrantes de la familia con cuenta propia
/// compartís su información de salud. Sin marcarlo, nadie la ve: las
/// reglas de Firestore y la pantalla de perfil respetan `sharedWithUids`.
class SharingSettingsScreen extends StatelessWidget {
  const SharingSettingsScreen({super.key});

  Future<void> _toggle(BuildContext context, FamilyProfile profile, String uid, bool share) async {
    final updated = profile.sharedWithUids.toSet();
    share ? updated.add(uid) : updated.remove(uid);
    try {
      await ProfileService.instance.setSharedWithUids(profile.id, updated.toList());
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el cambio. Intentá de nuevo.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: 'Compartir perfiles', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: StreamBuilder<List<FamilyProfile>>(
                stream: ProfileService.instance.watchProfiles(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return const Center(child: Text('No se pudieron cargar los perfiles.'));
                  }

                  final profiles = snap.data ?? const <FamilyProfile>[];
                  final mine = profiles.where((p) => p.ownerUid == myUid).toList();

                  // Integrantes con cuenta propia (uno por uid).
                  final candidates = <String, FamilyProfile>{};
                  for (final p in profiles) {
                    final uid = p.linkedUid;
                    if (uid != null && uid != myUid) candidates.putIfAbsent(uid, () => p);
                  }

                  final sharedWithMe = profiles
                      .where((p) => p.ownerUid != myUid && myUid != null && p.sharedWithUids.contains(myUid))
                      .toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      Text(
                        'Elegí quién de tu familia puede ver los datos de salud de cada perfil: '
                            'historial, medicación, agenda, signos vitales y recetas. '
                            'Nadie los ve si no lo marcás acá, y podés quitar el permiso cuando quieras.',
                        style: TextStyle(fontSize: 14, height: 1.45, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 20),
                      if (candidates.isEmpty)
                        _InfoBox(
                          icon: Icons.group_add_outlined,
                          text: 'Todavía no hay otros integrantes con cuenta propia en tu familia. '
                              'Cuando alguien se una, vas a poder compartirle tus perfiles desde acá.',
                        )
                      else
                        for (final p in mine) ...[
                          _ProfileSharingCard(
                            profile: p,
                            candidates: candidates,
                            onToggle: (uid, share) => _toggle(context, p, uid, share),
                          ),
                          const SizedBox(height: 14),
                        ],
                      if (sharedWithMe.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'COMPARTIDOS CONTIGO',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        for (final p in sharedWithMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _InfoBox(
                              icon: Icons.visibility_outlined,
                              text: '${p.fullName} compartió su información de salud con vos.',
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSharingCard extends StatelessWidget {
  final FamilyProfile profile;
  final Map<String, FamilyProfile> candidates;
  final void Function(String uid, bool share) onToggle;

  const _ProfileSharingCard({required this.profile, required this.candidates, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isPet = profile.type == ProfileType.mascota;
    final sharedNames = [
      for (final e in candidates.entries)
        if (profile.sharedWithUids.contains(e.key)) e.value.name,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isPet ? SaluteColors.terracotta : SaluteColors.darkGreen,
                child: Icon(isPet ? Icons.pets_outlined : Icons.person_outline, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.isSelf ? '${profile.name} (vos)' : profile.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sharedNames.isEmpty ? 'Solo vos' : 'Compartido con ${sharedNames.join(', ')}',
                      style: TextStyle(fontSize: 12, color: sharedNames.isEmpty ? Colors.grey[600] : SaluteColors.primaryGreen),
                    ),
                  ],
                ),
              ),
              Icon(
                sharedNames.isEmpty ? Icons.lock_outline : Icons.people_alt_outlined,
                color: sharedNames.isEmpty ? Colors.grey[400] : SaluteColors.primaryGreen,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final e in candidates.entries)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: SaluteColors.primaryGreen,
              title: Text(e.value.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              value: profile.sharedWithUids.contains(e.key),
              onChanged: (v) => onToggle(e.key, v),
            ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SaluteColors.lightGreen.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SaluteColors.primaryGreen, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }
}