import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/components/profile_avatar.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/core/settingsScreen.dart';
import 'package:saluteapp/profile/live_profile_screen.dart';
import 'package:saluteapp/profile/profile_form_screen.dart';

/// Pestaña PERFIL: lista en tiempo real de todos los perfiles
/// (personas y mascotas) del usuario logueado, con alta/edición.
class FamilyListScreen extends StatelessWidget {
  final VoidCallback? onBackToDashboard;

  const FamilyListScreen({super.key, this.onBackToDashboard});

  void _openProfile(BuildContext context, FamilyProfile profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveProfileScreen(
          profile: profile,
          onEdit: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileFormScreen(existingProfile: profile)),
            );
          },
        ),
      ),
    );
  }

  void _openNewProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Mi familia',
              onBack: onBackToDashboard,
              onSettings: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(onBackToDashboard: () => Navigator.of(context).pop()),
                  ),
                );
              },
            ),
            Expanded(
              child: StreamBuilder<List<FamilyProfile>>(
                stream: ProfileService.instance.watchProfiles(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudieron cargar los perfiles.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: SaluteColors.textMuted),
                        ),
                      ),
                    );
                  }
                  final profiles = snapshot.data ?? [];
                  // "Mío" se decide por quién ADMINISTRA el perfil (ownerUid),
                  // no por `isSelf`: el perfil propio de otro integrante de
                  // la familia también tiene isSelf == true (es el suyo), y
                  // antes por eso caía acá en "Vos y tus dependientes".
                  final myUid = FirebaseAuth.instance.currentUser?.uid;
                  final mine = profiles.where((p) => p.ownerUid == myUid).toList();
                  final others = profiles.where((p) => p.ownerUid != myUid).toList();
                  // Candidatos para compartir datos clínicos: los demás
                  // integrantes con cuenta propia (no sus dependientes).
                  final accountMembers = others.where((p) => !p.isDependent).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      if (profiles.isEmpty)
                        _EmptyState(onAdd: () => _openNewProfile(context))
                      else ...[
                        if (others.isNotEmpty) ...[
                          _SectionLabel('Miembros de la familia'),
                          const SizedBox(height: 10),
                          for (final p in others) ...[
                            _ProfileListTile(
                              profile: p,
                              onTap: () => _openProfile(context, p),
                              familyMembers: accountMembers,
                            ),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 8),
                        ],
                        _SectionLabel(others.isEmpty ? 'Perfiles' : 'Vos y tus dependientes'),
                        const SizedBox(height: 10),
                        for (final p in mine) ...[
                          _ProfileListTile(
                            profile: p,
                            onTap: () => _openProfile(context, p),
                            familyMembers: accountMembers,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar perfil',
        backgroundColor: SaluteColors.primaryGreen,
        onPressed: () => _openNewProfile(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: SaluteColors.textMuted,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _ProfileListTile extends StatelessWidget {
  final FamilyProfile profile;
  final VoidCallback onTap;
  final List<FamilyProfile> familyMembers;

  const _ProfileListTile({
    required this.profile,
    required this.onTap,
    required this.familyMembers,
  });

  Future<void> _openSharingSheet(BuildContext context) async {
    // Solo tiene sentido compartir con otros miembros que tengan cuenta
    // propia (a un dependiente no le podés "compartir" nada, no tiene
    // con qué iniciar sesión para ver algo).
    final candidates = familyMembers.where((m) => m.linkedUid != profile.linkedUid).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todavía no hay otros miembros con cuenta propia en tu familia.')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SharingSheet(profile: profile, candidates: candidates),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPet = profile.type == ProfileType.mascota;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    // Solo quien administra el perfil (tutor de un dependiente, o el
    // miembro independiente sobre su propio perfil) puede decidir con
    // quién se comparten sus datos clínicos.
    final canManageSharing = profile.ownerUid == myUid;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            ProfileAvatar.fromProfile(profile, radius: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: DsFontSize.xl, color: Colors.black87),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.relation.isNotEmpty ? profile.relation : (isPet ? 'Mascota' : 'Familiar'),
                    style: TextStyle(fontSize: DsFontSize.md, color: SaluteColors.textMuted),
                  ),
                ],
              ),
            ),
            if (profile.ownerUid != myUid && !profile.isDependent)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.28),
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: SaluteColors.lightGreen,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Cuenta propia',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SaluteColors.primaryGreen),
                ),
              )),
            if (canManageSharing)
              IconButton(
                onPressed: () => _openSharingSheet(context),
                tooltip: 'Compartir datos clínicos',
                icon: Icon(
                  profile.sharedWithUids.isEmpty ? Icons.lock_outline : Icons.people_alt_outlined,
                  size: 20,
                  color: profile.sharedWithUids.isEmpty ? SaluteColors.textMuted : SaluteColors.primaryGreen,
                ),
              )
            else
              Icon(Icons.chevron_right, color: SaluteColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet para elegir con qué miembros (con cuenta propia) se
/// comparten los datos clínicos de `profile`. No pregunta nada sobre la
/// existencia del perfil en sí —eso ya es visible para toda la
/// familia—, solo sobre su información de salud detallada (agenda,
/// métricas, historial, vacunas, medicación, recetas).
class _SharingSheet extends StatefulWidget {
  final FamilyProfile profile;
  final List<FamilyProfile> candidates;
  const _SharingSheet({required this.profile, required this.candidates});

  @override
  State<_SharingSheet> createState() => _SharingSheetState();
}

class _SharingSheetState extends State<_SharingSheet> {
  late Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.profile.sharedWithUids.toSet();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ProfileService.instance.setSharedWithUids(widget.profile.id, _selected.toList());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compartir datos de ${widget.profile.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            Text(
              'Agenda, métricas, historial, vacunas, medicación y recetas. '
              'Nadie ve esto salvo que lo marques acá.',
              style: TextStyle(fontSize: DsFontSize.md, color: SaluteColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final member in widget.candidates)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(member.linkedUid),
                onChanged: (checked) {
                  setState(() {
                    if (checked ?? false) {
                      _selected.add(member.linkedUid!);
                    } else {
                      _selected.remove(member.linkedUid);
                    }
                  });
                },
                title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                activeColor: SaluteColors.primaryGreen,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: SaluteColors.primaryGreen),
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.family_restroom, size: 48, color: SaluteColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Todavía no agregaste a nadie de tu familia.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SaluteColors.textMuted, fontSize: DsFontSize.md),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(backgroundColor: SaluteColors.primaryGreen),
              icon: const Icon(Icons.add),
              label: const Text('Agregar perfil'),
            ),
          ],
        ),
      ),
    );
  }
}
