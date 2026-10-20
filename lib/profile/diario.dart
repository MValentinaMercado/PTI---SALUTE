import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/active_profile_selector.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/active_profile_controller.dart';
import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/services/agenda_service.dart';
import 'package:saluteapp/core/services/medical_record_service.dart';
import 'package:saluteapp/personal/agenda.dart';
import 'package:saluteapp/personal/triaje.dart';
import 'package:saluteapp/personal/tracker.dart';
import 'package:saluteapp/personal/metricas.dart';
import 'package:saluteapp/personal/botiquin.dart';
import 'package:saluteapp/profile/consultas_screen.dart';
import 'package:saluteapp/profile/medical_sheet_screen.dart';
import 'package:saluteapp/profile/medication_form_screen.dart';
import 'package:saluteapp/profile/orden.dart';
import 'package:saluteapp/profile/pet_weight_screen.dart';
import 'package:saluteapp/profile/vaccine_card_screen.dart';

/// Perfil sobre el que trabajan Triaje, Estado emocional y Métricas cuando se entra
/// desde acá (Diario) sin tener ya un perfil puntual en pantalla —a
/// diferencia de LiveProfileScreen, que sí lo tiene—. BUG-006 (Parte 3):
/// antes, cada una de las tres pantallas preguntaba "¿para quién?" con
/// su propio selector duplicado; ahora las tres usan el mismo perfil
/// activo global (ver `ActiveProfileController`). Si el usuario
/// quiere registrar algo para otro perfil, cambia el activo desde ahí.
FamilyProfile? _requireActiveProfile(BuildContext context) {
  final active = ActiveProfileController.instance.active;
  if (active == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Esperá a que cargue tu perfil para continuar.')),
    );
  }
  return active;
}

Future<void> _openTriaje(BuildContext context) async {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BitacoraTriajeScreen(profileId: target.id, profileName: target.name),
    ),
  );
}

void _openMoodTracker(BuildContext context) {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MoodTrackerScreen(profileId: target.id, profileName: target.name),
    ),
  );
}

/// Ficha médica del perfil activo. Con [startWithShare] abre directo la hoja
/// de compartir (botón "Compartir datos"); sin él, muestra la ficha para
/// revisarla, copiarla o guardarla como PDF.
void _openMedicalSheet(BuildContext context, {bool startWithShare = false}) {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MedicalSheetScreen(
        profileId: target.id,
        profileName: target.name,
        startWithShare: startWithShare,
      ),
    ),
  );
}

/// Alta de un tratamiento (medicación con horarios y alertas) para el
/// perfil activo. Es distinto de Mi Botiquín, que es solo inventario.
void _openNewTreatment(BuildContext context) {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MedicationFormScreen(profileId: target.id, profileName: target.name),
    ),
  );
}

/// BiometricsScreen necesita un perfil puntual, misma razón que Triaje
/// y Estado emocional: se accede desde acá sin perfil en contexto.
void _openBiometrics(BuildContext context) {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BiometricsScreen(profileId: target.id, profileName: target.name),
    ),
  );
}

// =============================================================================
// DIARIO SCREEN - Main Screen
// =============================================================================

/// `true` si el usuario logueado administra este perfil (es el suyo o un
/// dependiente suyo). Es la misma condición que exigen las reglas de
/// Firestore para ESCRIBIR (`request.auth.uid == profile.uid`): quien solo
/// tiene acceso compartido puede leer, pero no cargar datos.
bool _isMine(FamilyProfile p) => p.ownerUid == FirebaseAuth.instance.currentUser?.uid;

/// Carné de vacunación del perfil activo. El carné vive en el perfil
/// (`LiveProfileScreen`) y esto es un acceso directo a la misma pantalla.
void _openVaccines(BuildContext context) {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => VaccineCardScreen(profile: target)),
  );
}

/// Consultas (visitas al veterinario / médico) del perfil activo. Son lo que
/// llena el "Historial" de la ficha.
void _openConsultas(BuildContext context) {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ConsultasScreen(profile: target)),
  );
}

/// Órdenes (estudios, laboratorio, cardiología) del perfil activo. Es la misma
/// pantalla de la pestaña Órdenes, acotada a este perfil.
void _openOrders(BuildContext context) {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => OrdenScreen(profile: target)),
  );
}

/// Historial de peso de una mascota (solo se ofrece para perfiles mascota).
void _openPetWeight(BuildContext context) {
  final target = _requireActiveProfile(context);
  if (target == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PetWeightScreen(profile: target)),
  );
}

class DiarioScreen extends StatelessWidget {
  final VoidCallback? onBackToDashboard;

  const DiarioScreen({super.key, this.onBackToDashboard});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _DiarioAppBar(onBackToDashboard: onBackToDashboard),
            Expanded(
              // Todo el contenido depende del perfil activo: al cambiarlo
              // desde el selector, el Diario se reconstruye entero (y pasa
              // de "persona" a "mascota" si corresponde).
              child: ListenableBuilder(
                listenable: ActiveProfileController.instance,
                builder: (context, _) {
                  final active = ActiveProfileController.instance.active;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ActiveProfileSelector(),
                        const SizedBox(height: 16),
                        if (active == null)
                          const _InfoNote(text: 'Cargando tu perfil…')
                        else if (!_isMine(active))
                          _InfoNote(
                            text: 'Estás viendo a ${active.name} en modo lectura. '
                                'Para cargar datos, elegí tu perfil o el de un dependiente tuyo.',
                          )
                        else if (active.type == ProfileType.mascota)
                            _PetBody(profile: active)
                          else
                            _PersonBody(profile: active),
                      ],
                    ),
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

/// Diario de una persona (vos o un dependiente tuyo, ej. un hijo).
class _PersonBody extends StatelessWidget {
  final FamilyProfile profile;
  const _PersonBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TriajeCard(key: ValueKey('triaje-${profile.id}'), profile: profile),
        const SizedBox(height: 12),
        _HitoCard(key: ValueKey('hito-${profile.id}'), profile: profile),
        const SizedBox(height: 28),
        _AccesosGroup(
          title: 'Seguimiento',
          color: SaluteColors.brownOrange,
          items: [
            _AccesoItem(
              icon: Icons.calendar_month_outlined,
              label: 'MI AGENDA',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgendaScreen())),
            ),
            _AccesoItem(
              icon: Icons.add_box_outlined,
              label: 'TRIAJE SOAP',
              onTap: () => _openTriaje(context),
            ),
            _AccesoItem(
              icon: Icons.emoji_emotions_outlined,
              label: 'ESTADO EMOCIONAL',
              onTap: () => _openMoodTracker(context),
            ),
            _AccesoItem(
              icon: Icons.favorite_border,
              label: 'BIO-MÉT.',
              onTap: () => _openBiometrics(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _AccesosGroup(
          title: 'Salud',
          color: SaluteColors.primaryGreen,
          items: [
            _AccesoItem(
              icon: Icons.vaccines_outlined,
              label: 'CARNÉ DE VACUNAS',
              onTap: () => _openVaccines(context),
            ),
            _AccesoItem(
              icon: Icons.medical_services_outlined,
              label: 'MI BOTIQUÍN',
              onTap: () => _openBotiquin(context),
            ),
            _AccesoItem(
              icon: Icons.medication_outlined,
              label: 'NUEVO TRATAMIENTO',
              onTap: () => _openNewTreatment(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _AyudaCard(),
      ],
    );
  }
}

/// Diario de una mascota. Triaje SOAP, estado emocional, bio-métricas
/// (sueño, pasos, estrés) y el contacto SOS humano no aplican, así que no
/// se muestran. Al final lleva la misma tarjeta "¿Necesitas ayuda?" que las
/// personas; lo que se comparte es la ficha veterinaria (ver
/// `MedicalSheetData`), sin datos de personas.
class _PetBody extends StatelessWidget {
  final FamilyProfile profile;
  const _PetBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HitoCard(key: ValueKey('hito-${profile.id}'), profile: profile),
        const SizedBox(height: 28),
        _AccesosGroup(
          title: 'Cuidado de su salud',
          color: SaluteColors.primaryGreen,
          items: [
            _AccesoItem(
              icon: Icons.assignment_outlined,
              label: 'CONSULTAS',
              onTap: () => _openConsultas(context),
            ),
            _AccesoItem(
              icon: Icons.description_outlined,
              label: 'ÓRDENES',
              onTap: () => _openOrders(context),
            ),
            _AccesoItem(
              icon: Icons.vaccines_outlined,
              label: 'CARNÉ DE VACUNAS',
              onTap: () => _openVaccines(context),
            ),
            _AccesoItem(
              icon: Icons.medication_outlined,
              label: 'NUEVO TRATAMIENTO',
              onTap: () => _openNewTreatment(context),
            ),
            _AccesoItem(
              icon: Icons.medical_services_outlined,
              label: 'BOTIQUÍN',
              onTap: () => _openBotiquin(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _AccesosGroup(
          title: 'Seguimiento',
          color: SaluteColors.brownOrange,
          items: [
            _AccesoItem(
              icon: Icons.calendar_month_outlined,
              label: 'AGENDA',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgendaScreen())),
            ),
            _AccesoItem(
              icon: Icons.monitor_weight_outlined,
              label: 'PESO',
              onTap: () => _openPetWeight(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _AyudaCard(isPet: true),
      ],
    );
  }
}

void _openBotiquin(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => BotiquinScreen(onBackToDashboard: () => Navigator.maybePop(context))),
  );
}

/// Aviso simple (cargando / modo lectura).
class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SaluteColors.cardBeige,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.35),
      ),
    );
  }
}

// =============================================================================
// APP BAR
// =============================================================================

class _DiarioAppBar extends StatelessWidget {
  final VoidCallback? onBackToDashboard;

  const _DiarioAppBar({this.onBackToDashboard});

  @override
  Widget build(BuildContext context) {
    return AppHeader.secondary(
      title: 'Diario',
      onBack: onBackToDashboard,
    );
  }
}

// =============================================================================
// CARD COMPONENTS
// =============================================================================

/// Card showing current triage index level
const _triageLevelLabels = {1: 'Nivel 1 (Emergencia)', 2: 'Nivel 2 (Urgencia)', 3: 'Nivel 3 (Estable)'};

/// Último registro de triaje del perfil ACTIVO (antes recorría todos los
/// perfiles de la familia). Si la lectura falla (ej. sin permiso), devuelve
/// null y la tarjeta muestra "Sin registros" en vez de romper la pantalla.
Future<_LatestTriage?> _fetchLatestTriage(FamilyProfile profile) async {
  try {
    // fetchRecords trae todas las categorías del historial; nos quedamos
    // con la más reciente que sea de triaje (viene ordenado desc por
    // fecha, pero el registro más nuevo del perfil puede ser de otra
    // categoría).
    final records = await MedicalRecordService.instance.fetchRecords(profile.id, limit: 10);
    for (final r in records) {
      if (r.category == RecordCategory.triaje) {
        return _LatestTriage(
          profileName: profile.name,
          level: (r.details['nivel'] as num?)?.toInt() ?? 3,
          date: r.date,
        );
      }
    }
  } on FirebaseException catch (e) {
    debugPrint('Diario: no se pudo leer el historial de ${profile.id}. $e');
  }
  return null;
}

class _LatestTriage {
  final String profileName;
  final int level;
  final DateTime date;
  const _LatestTriage({required this.profileName, required this.level, required this.date});
}

class _TriajeCard extends StatefulWidget {
  final FamilyProfile profile;
  const _TriajeCard({super.key, required this.profile});

  @override
  State<_TriajeCard> createState() => _TriajeCardState();
}

class _TriajeCardState extends State<_TriajeCard> {
  late Future<_LatestTriage?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchLatestTriage(widget.profile);
  }

  @override
  void didUpdateWidget(covariant _TriajeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _future = _fetchLatestTriage(widget.profile);
    }
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} día(s)';
  }

  Future<void> _open() async {
    await _openTriaje(context);
    // Al volver, refresca: seguramente se cargó un triaje nuevo.
    if (mounted) setState(() => _future = _fetchLatestTriage(widget.profile));
  }

  Color _levelColor(int? level) {
    switch (level) {
      case 1:
        return const Color(0xFFB03A3A);
      case 2:
        return SaluteColors.warning;
      case 3:
        return SaluteColors.primaryGreen;
      default:
        return SaluteColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LatestTriage?>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final latest = snapshot.data;
        final color = _levelColor(loading ? null : latest?.level);

        return Semantics(
          button: true,
          label: 'Índice de triaje actual',
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: _open,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: color.withValues(alpha: 0.18), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.08)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.monitor_heart_outlined, color: color, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ÍNDICE DE TRIAJE ACTUAL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: SaluteColors.textMuted,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            loading
                                ? 'Cargando...'
                                : (latest != null
                                ? (_triageLevelLabels[latest.level] ?? 'Nivel ${latest.level}')
                                : 'Sin registros'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: latest != null ? color : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            loading
                                ? ''
                                : (latest != null
                                ? '${latest.profileName} · ${_timeAgo(latest.date)}'
                                : 'Tocá para cargar el primer triaje de ${widget.profile.name}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: SaluteColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.chevron_right_rounded, color: color, size: 24),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const _hitoIcons = {
  AgendaEventType.turno: Icons.event_available,
  AgendaEventType.estudio: Icons.biotech_outlined,
  AgendaEventType.vacuna: Icons.vaccines_outlined,
  AgendaEventType.control: Icons.monitor_heart_outlined,
  AgendaEventType.medicacion: Icons.medication_outlined,
  AgendaEventType.otro: Icons.event_note_outlined,
};

/// Próximo hito (turno, vacuna, control...) del perfil ACTIVO. Antes tomaba
/// el próximo evento de cualquier perfil de la familia; ahora usa
/// `AgendaService.watchNextForProfile`, así coincide con el selector.
class _HitoCard extends StatefulWidget {
  final FamilyProfile profile;
  const _HitoCard({super.key, required this.profile});

  @override
  State<_HitoCard> createState() => _HitoCardState();
}

class _HitoCardState extends State<_HitoCard> {
  // Se crea una sola vez por perfil (el padre usa `ValueKey(profile.id)`),
  // para no volver a suscribirse a Firestore en cada rebuild.
  late final Stream<AgendaEvent?> _stream = AgendaService.instance.watchNextForProfile(widget.profile.id);

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Hoy, $time';
    if (diff == 1) return 'Mañana, $time';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}, $time';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AgendaEvent?>(
      stream: _stream,
      builder: (context, snapshot) {
        // Si la lectura falla (ej. sin permiso) se muestra como "sin turnos".
        final next = snapshot.hasError ? null : snapshot.data;
        final loading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasError;
        const color = SaluteColors.brownOrange;

        return Semantics(
          button: true,
          label: 'Próximo hito, abrir agenda',
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgendaScreen())),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: color.withValues(alpha: 0.18), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.08)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        next != null ? (_hitoIcons[next.type] ?? Icons.event_note_outlined) : Icons.event_note_outlined,
                        color: color,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PRÓXIMO HITO · ${widget.profile.name.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: SaluteColors.textMuted,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            loading ? 'Cargando...' : (next?.title ?? 'Sin próximos turnos'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (next != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: SaluteColors.lightGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_outlined, size: 13, color: SaluteColors.primaryGreen),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatDate(next.date),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: SaluteColors.primaryGreen,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (!loading)
                            Text(
                              'Agregá un turno desde la agenda',
                              style: TextStyle(fontSize: 12.5, color: SaluteColors.textMuted, fontWeight: FontWeight.w500),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_right_rounded, color: color, size: 24),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Grupo de accesos directos: un título y una grilla de tarjetas (3 por
/// fila). Los items los arma cada cuerpo (persona / mascota), porque no son
/// los mismos.
class _AccesosGroup extends StatelessWidget {
  final String title;
  final Color color;
  final List<_AccesoItem> items;
  const _AccesosGroup({required this.title, required this.color, required this.items});

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - spacing * 2) / 3;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: items
                  .map((item) => SizedBox(width: tileWidth, child: _AccesoButton(item: item, color: color)))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

/// Model for quick access items
class _AccesoItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AccesoItem({required this.icon, required this.label, required this.onTap});
}

/// Tarjeta de un acceso directo.
class _AccesoButton extends StatelessWidget {
  final _AccesoItem item;
  final Color color;
  const _AccesoButton({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: item.label,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: const BoxConstraints(minHeight: 104),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: color, size: 25),
                ),
                const SizedBox(height: 10),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[800],
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// El "Protocolo de Emergencia" (contacto SOS) vive en el Perfil de cada persona
// (ver `FamiliarProfileScreen`), con el estilo del resto de esa pantalla.

/// Tarjeta de ayuda, igual para personas y mascotas: un único botón que abre
/// la ficha lista para compartir. La hoja de compartir ya deja revisar la
/// vista previa, copiar el texto o guardarlo como PDF, así que no hace falta
/// un segundo botón solo para "ver la ficha" (sigue en el Perfil).
class _AyudaCard extends StatelessWidget {
  final bool isPet;
  const _AyudaCard({this.isPet = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SaluteColors.cardBeige,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SaluteColors.cardBeige.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Necesitas ayuda?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: SaluteColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isPet
                ? 'Compartí la ficha veterinaria con quien la necesite, eligiendo qué datos incluir.'
                : 'Compartí tu ficha médica con quien la necesite, eligiendo qué datos incluir.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.35),
          ),
          const SizedBox(height: 16),
          _AccesoSimpleButton(
            icon: Icons.share_outlined,
            label: 'COMPARTIR DATOS',
            onTap: () => _openMedicalSheet(context, startWithShare: true),
          ),
        ],
      ),
    );
  }
}

/// Botón de ancho completo de la tarjeta de ayuda.
class _AccesoSimpleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AccesoSimpleButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SaluteColors.primaryGreen.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: SaluteColors.primaryGreen, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: SaluteColors.primaryGreen,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
