import 'package:saluteapp/components/text_scale.dart';
import 'package:saluteapp/components/a11y_tap.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/components/medication_today_card.dart';
import 'package:saluteapp/components/profile_avatar.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/models/family.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/services/agenda_service.dart';
import 'package:saluteapp/core/services/family_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/core/services/notifications_service.dart';
import 'package:saluteapp/profile/family_group_screen.dart';
import 'package:saluteapp/profile/family_list_screen.dart';
import 'package:saluteapp/profile/live_profile_screen.dart';
import 'package:saluteapp/profile/profile_form_screen.dart';
import 'package:saluteapp/profile/notifications_screen.dart';
import 'package:saluteapp/sos/sos_button.dart' show SosDashboardSlot;

/// Nombre de respaldo para el saludo, mientras se carga el perfil propio
/// (ver `_HealthCard`, que usa `ProfileService.watchSelfProfile()` como
/// fuente principal) o si por algún motivo ese perfil todavía no existe.
String _fallbackGreetingName() {
  final user = AuthService.instance.currentUser;
  final email = user?.email;
  if (email != null && email.contains('@')) return email.split('@').first;
  return 'Usuario';
}

class SaluteHomeScreen extends StatefulWidget {
  final VoidCallback? onLogoTap;
  const SaluteHomeScreen({super.key, this.onLogoTap});

  @override
  State<SaluteHomeScreen> createState() => _SaluteHomeScreenState();
}

class _SaluteHomeScreenState extends State<SaluteHomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cada vez que se muestra el Home se verifica si hay notificaciones.
    NotificationsService.instance.refreshUnread();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Volver a la app después de un rato: pudo vencer un turno, etc.
    if (state == AppLifecycleState.resumed) {
      NotificationsService.instance.refreshUnread();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: Stack(
        children: [
      SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: NotificationsService.instance.unreadBadge,
                builder: (context, unread, _) {
                  return AppHeader.dashboard(
                    onLogoTap: widget.onLogoTap,
                    showNotificationBadge: unread > 0,
                    onNotifications: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NotificationsScreen(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                      // NotificationsScreen ya actualiza el puntito en
                      // cada cambio; esto es solo una verificación extra
                      // al volver.
                      NotificationsService.instance.refreshUnread();
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _HealthCard(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _FamilySection(),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: MedicationTodayCard(),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _UpcomingTasks(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _MedicalConsultations(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      // SOS fijo en el Inicio (solo si está activado en Configuración).
      const SosDashboardSlot(),
        ],
      ),
    );
  }
}


/// Tarjeta de saludo del dashboard. Fusiona lo que antes eran dos
/// tarjetas separadas: el saludo ("¡Hola, X! Tu familia está bien
/// cuidada hoy.") y el banner de familia que vivía arriba de todo en
/// "Mi familia" (nombre + código, o la invitación a crear una si
/// todavía no tenés). Tocar la franja de abajo lleva a
/// FamilyGroupScreen, igual que antes hacía ese banner.
class _HealthCard extends StatelessWidget {
  const _HealthCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      decoration: BoxDecoration(
        color: SaluteColors.primaryGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<FamilyProfile?>(
            stream: ProfileService.instance.watchSelfProfile(),
            builder: (context, snapshot) {
              final self = snapshot.data;
              final greetingName = self?.displayUsername ?? _fallbackGreetingName();
              return Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: self != null && self.avatarUrl.isNotEmpty
                        ? ProfileAvatar.fromProfile(self, radius: 26)
                        : CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            child: const Icon(Icons.person, color: Colors.white, size: 28),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¡Hola, $greetingName!',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: DsFontSize.xl,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Tu familia esta bien cuidada hoy.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: DsFontSize.md,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),
          StreamBuilder<Family?>(
            stream: FamilyService.instance.watchMyFamily(),
            builder: (context, snapshot) {
              final family = snapshot.data;
              return _FamilyStatusRow(family: family);
            },
          ),
        ],
      ),
    );
  }
}

class _FamilyStatusRow extends StatelessWidget {
  final Family? family;
  const _FamilyStatusRow({required this.family});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FamilyGroupScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              family != null ? Icons.family_restroom : Icons.add_circle_outline,
              color: Colors.white.withValues(alpha: 0.9),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    family != null ? family!.name : 'Creá tu familia',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: DsFontSize.base,
                    ),
                  ),
                  Text(
                    family != null ? 'Código: ${family!.code}' : 'Creá una o unite con un código',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.85), size: 20),
          ],
        ),
      ),
    );
  }
}

class _FamilySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Family?>(
      // Si ya tenés familia, "Ver todos" lleva a administrarla; si
      // todavía no, el mismo lugar invita a crear una. Es la única
      // puerta de entrada a "familia" en toda la app —antes esto
      // también vivía en la pestaña PERFIL del nav (ahora es tu perfil
      // propio) y quedaba duplicado—.
      stream: FamilyService.instance.watchMyFamily(),
      builder: (context, familySnap) {
        final family = familySnap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'MI FAMILIA',
                    style: TextStyle(
                      fontSize: DsFontSize.base,
                      fontWeight: FontWeight.w600,
                      color: SaluteColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                A11yTap(
                  label: family != null ? 'Ver todos los familiares' : 'Crear familia',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FamilyListScreen(
                        onBackToDashboard: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  child: Text(
                    family != null ? 'Ver todos' : '+ Crear familia',
                    style: const TextStyle(
                      fontSize: DsFontSize.md,
                      fontWeight: FontWeight.w600,
                      color: SaluteColors.terracotta,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: scaledHeight(context, 64),
              child: StreamBuilder<List<FamilyProfile>>(
                stream: ProfileService.instance.watchProfiles(),
                builder: (context, snapshot) {
                  final profiles = snapshot.data ?? [];
                  // Scroll horizontal: con muchos perfiles la fila ya no desborda.
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                    children: [
                      ...profiles.map((profile) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: A11yTap(
                          label: 'Ver perfil de ${profile.name}',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LiveProfileScreen(
                                  profile: profile,
                                  onEdit: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ProfileFormScreen(existingProfile: profile),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                          child: Tooltip(
                            message: profile.name,
                            child: ProfileAvatar.fromProfile(profile, radius: 26, showInitial: true),
                          ),
                        ),
                      )),
                      A11yTap(
                        label: 'Agregar un perfil',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
                          );
                        },
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.grey[200],
                          child: Icon(Icons.add, color: SaluteColors.textMuted),
                        ),
                      ),
                    ],
                  ));
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UpcomingTasks extends StatelessWidget {
  const _UpcomingTasks();

  /// BUG-007: antes esto eran 2 `_TaskCard` hardcodeadas ("Azul - Vacuna",
  /// "Coty - Endoscopia"). Ahora sale de `AgendaService.watchAll()`,
  /// filtrando eventos pendientes y tomando los 2 más próximos por fecha
  /// (mismo criterio que usa `AgendaEvent.isUpcoming`).
  static const _typeIcons = {
    AgendaEventType.turno: Icons.event_available,
    AgendaEventType.estudio: Icons.biotech_outlined,
    AgendaEventType.vacuna: Icons.vaccines_outlined,
    AgendaEventType.control: Icons.monitor_heart_outlined,
    AgendaEventType.medicacion: Icons.medication_outlined,
    AgendaEventType.otro: Icons.event_note_outlined,
  };

  String _badgeFor(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = day.difference(today).inDays;
    if (diff <= 0) return 'HOY';
    if (diff == 1) return 'MAÑANA';
    return 'PRÓXIMO';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Proximas Tareas',
          style: TextStyle(
            fontSize: DsFontSize.h4,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 14),
        StreamBuilder<List<AgendaEvent>>(
          stream: AgendaService.instance.watchAll(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final upcoming = (snapshot.data ?? const <AgendaEvent>[])
                .where((e) => e.isUpcoming)
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date));
            if (upcoming.isEmpty) {
              return Text(
                'No tenés tareas próximas.',
                style: TextStyle(color: SaluteColors.textMuted, fontSize: DsFontSize.md),
              );
            }
            final items = upcoming.take(2).toList();
            return Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _TaskCard(
                    name: items[i].profileName,
                    task: items[i].title,
                    iconBg: items[i].type == AgendaEventType.vacuna
                        ? SaluteColors.lightBrown
                        : SaluteColors.lightGreen,
                    iconData: _typeIcons[items[i].type] ?? Icons.event_note_outlined,
                    iconColor: items[i].type == AgendaEventType.vacuna
                        ? SaluteColors.brownOrange
                        : SaluteColors.primaryGreen,
                    badge: _badgeFor(items[i].date),
                    badgeBg: items[i].type == AgendaEventType.vacuna
                        ? SaluteColors.lightBrown
                        : SaluteColors.lightGreen,
                    badgeTextColor: items[i].type == AgendaEventType.vacuna
                        ? SaluteColors.brownOrange
                        : SaluteColors.primaryGreen,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final String name;
  final String task;
  final Color iconBg;
  final IconData iconData;
  final Color iconColor;
  final String badge;
  final Color badgeBg;
  final Color badgeTextColor;

  const _TaskCard({
    required this.name,
    required this.task,
    required this.iconBg,
    required this.iconData,
    required this.iconColor,
    required this.badge,
    required this.badgeBg,
    required this.badgeTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(iconData, color: iconColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: DsFontSize.xl,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  task,
                  style: TextStyle(fontSize: DsFontSize.md, color: SaluteColors.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: badgeTextColor,
                fontSize: DsFontSize.sm,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _monthLabels = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

class _MedicalConsultations extends StatelessWidget {
  /// BUG-008: antes eran 2 `_ConsultationCard` hardcodeadas ("VETERINARIA
  /// PG - Control Azul", "CLINICA - Dr. Garcia"). Ahora salen de la misma
  /// `AgendaService.watchAll()` que usa `_UpcomingTasks` y la pantalla de
  /// Agenda: acá no debería haber una fuente de datos médicos separada
  /// (ver nota de tu doc: "no deberías tener información médica
  /// duplicada"), solo una vista distinta sobre los mismos eventos.
  String _formatDate(DateTime d) => '${d.day} de ${_monthLabels[d.month - 1]}';

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Consultas Medicas',
                style: TextStyle(
                  fontSize: DsFontSize.h4,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Ver historial',
              style: TextStyle(fontSize: DsFontSize.md, color: SaluteColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: scaledHeight(context, 170),
          child: StreamBuilder<List<AgendaEvent>>(
            stream: AgendaService.instance.watchAll(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final upcoming = (snapshot.data ?? const <AgendaEvent>[])
                  .where((e) => e.isUpcoming)
                  .toList()
                ..sort((a, b) => a.date.compareTo(b.date));
              if (upcoming.isEmpty) {
                return Center(
                  child: Text(
                    'No hay consultas próximas.',
                    style: TextStyle(color: SaluteColors.textMuted, fontSize: DsFontSize.md),
                  ),
                );
              }
              final items = upcoming.take(4).toList();
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final event = items[i];
                  final isDark = i == 0;
                  return _ConsultationCard(
                    clinic: event.location.isNotEmpty ? event.location : event.profileName,
                    title: event.title,
                    date: _formatDate(event.date),
                    time: _formatTime(event.date),
                    cardColor: isDark ? SaluteColors.primaryGreen : const Color(0xFFEEEEEE),
                    isDark: isDark,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConsultationCard extends StatelessWidget {
  final String clinic;
  final String title;
  final String date;
  final String time;
  final Color cardColor;
  final bool isDark;

  const _ConsultationCard({
    required this.clinic,
    required this.title,
    required this.date,
    required this.time,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor =
    isDark ? Colors.white.withValues(alpha: 0.85) : SaluteColors.textMuted;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clinic,
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: DsFontSize.sm,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: DsFontSize.xxl,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date,
                    style: TextStyle(color: subtitleColor, fontSize: DsFontSize.md),
                  ),
                  Text(
                    time,
                    style: TextStyle(
                      color: textColor,
                      fontSize: DsFontSize.md,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (isDark)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}