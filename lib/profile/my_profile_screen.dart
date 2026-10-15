import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/profile/live_profile_screen.dart';
import 'package:saluteapp/profile/profile_form_screen.dart';

/// Pestaña PERFIL del nav: el perfil del propio usuario autenticado
/// (no la lista de toda la familia —eso vive en "Mi familia", que ahora
/// se accede desde el Home tocando "Ver todos"; tenerlo en los dos
/// lugares era redundante—).
class MyProfileScreen extends StatelessWidget {
  final VoidCallback? onBackToDashboard;

  const MyProfileScreen({super.key, this.onBackToDashboard});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FamilyProfile>>(
      stream: ProfileService.instance.watchProfiles(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se pudo cargar tu perfil.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          );
        }

        final profiles = snapshot.data ?? const <FamilyProfile>[];
        // El perfil propio es el `isSelf` que administra ESTE usuario: en una
        // familia hay un `isSelf` por integrante (ver `ProfileService.selfOf`).
        final FamilyProfile? self = ProfileService.selfOf(
          profiles,
          FirebaseAuth.instance.currentUser?.uid,
        );

        if (self == null) {
          // No debería pasar —BUG-001 crea el perfil propio
          // automáticamente al registrarse—, pero por las dudas no
          // dejamos la pestaña en blanco sin explicación.
          return const Scaffold(
            body: Center(child: Text('Todavía no encontramos tu perfil. Probá reingresar.')),
          );
        }

        return LiveProfileScreen(
          profile: self,
          onBackToDashboard: onBackToDashboard,
          onEdit: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileFormScreen(existingProfile: self)),
            );
          },
        );
      },
    );
  }
}
