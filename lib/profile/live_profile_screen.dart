import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/family_profile_mapper.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/models/sos_contact.dart';
import 'package:saluteapp/core/models/vital_entry.dart';
import 'package:saluteapp/core/services/agenda_service.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/core/services/sos_contact_service.dart';
import 'package:saluteapp/core/services/vitals_service.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/components/profile_avatar.dart';
import 'package:saluteapp/core/contacts.dart';
import 'package:saluteapp/personal/metricas.dart';
import 'package:saluteapp/profile/medical_sheet_screen.dart';
import 'package:saluteapp/profile/medication_checklist_screen.dart';
import 'package:saluteapp/profile/medication_form_screen.dart';
import 'package:saluteapp/profile/pet_weight_screen.dart';
import 'package:saluteapp/profile/profileCard.dart';
import 'package:saluteapp/profile/vaccine_card_screen.dart';

const _typeLabels = {
  AgendaEventType.turno: 'TURNO',
  AgendaEventType.estudio: 'ESTUDIO',
  AgendaEventType.vacuna: 'VACUNA',
  AgendaEventType.control: 'CONTROL',
  AgendaEventType.medicacion: 'MEDICACIÓN',
  AgendaEventType.otro: 'AGENDA',
};

const _typeIcons = {
  AgendaEventType.turno: Icons.event_available,
  AgendaEventType.estudio: Icons.biotech_outlined,
  AgendaEventType.vacuna: Icons.vaccines_outlined,
  AgendaEventType.control: Icons.monitor_heart_outlined,
  AgendaEventType.medicacion: Icons.medication_outlined,
  AgendaEventType.otro: Icons.event_note_outlined,
};

/// Conecta la UI ya existente de [FamiliarProfileScreen] a los datos
/// reales de Firestore: medicación activa (`profiles/{id}/medicacion`)
/// y el próximo evento de agenda (`agenda`, filtrado por profileId).
///
/// El resto de los campos (nombre, tipo de sangre, alergias, etc.) ya
/// vienen del perfil en sí, vía `toDisplayData()`.
class LiveProfileScreen extends StatefulWidget {
  final FamilyProfile profile;
  final VoidCallback? onEdit;
  final VoidCallback? onBackToDashboard;

  const LiveProfileScreen({
    super.key,
    required this.profile,
    this.onEdit,
    this.onBackToDashboard,
  });

  @override
  State<LiveProfileScreen> createState() => _LiveProfileScreenState();
}

class _LiveProfileScreenState extends State<LiveProfileScreen> {
  // Foto recién guardada. Cuando esta pantalla se abre con un perfil fijo
  // (ej. desde el Home) no recibe el cambio por stream, así que se muestra
  // la nueva foto de inmediato desde acá.
  String? _avatarOverride;

  @override
  void didUpdateWidget(covariant LiveProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si llegó un perfil actualizado (con su propia foto), manda ese.
    if (oldWidget.profile.avatarUrl != widget.profile.avatarUrl)
      _avatarOverride = null;
  }

  @override
  Widget build(BuildContext context) {
    final override = _avatarOverride;
    return _LiveProfileView(
      profile: override == null
          ? widget.profile
          : widget.profile.copyWith(avatarUrl: override),
      onEdit: widget.onEdit,
      onBackToDashboard: widget.onBackToDashboard,
      onAvatarChanged: (url) => setState(() => _avatarOverride = url),
    );
  }
}

class _LiveProfileView extends StatelessWidget {
  final FamilyProfile profile;
  final VoidCallback? onEdit;
  final VoidCallback? onBackToDashboard;
  final ValueChanged<String> onAvatarChanged;

  const _LiveProfileView({
    required this.profile,
    required this.onAvatarChanged,
    this.onEdit,
    this.onBackToDashboard,
  });

  /// Solo quien administra el perfil (el propio o un dependiente suyo) puede
  /// cambiarle la foto: es la misma condición que exigen las reglas de
  /// Firestore para escribir en `profiles/{id}`.
  bool get _canEditPhoto =>
      profile.ownerUid == FirebaseAuth.instance.currentUser?.uid;

  Future<void> _changePhoto(BuildContext context) async {
    final result = await AvatarPhoto.choose(
      context,
      hasPhoto: profile.avatarUrl.isNotEmpty,
    );
    if (result == null) return; // canceló
    try {
      await ProfileService.instance.setAvatar(profile.id, result);
      onAvatarChanged(result);
    } catch (e) {
      debugPrint('LiveProfileScreen: no se pudo guardar la foto. $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar la foto. Intentá de nuevo.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _formatTimes(List<String> times) =>
      times.isEmpty ? 'Sin horario' : times.join(' / ');

  List<FamilyAlertData> _buildAlerts(
    AgendaEvent? nextEvent,
    List<Medication> medications,
  ) {
    final alerts = <FamilyAlertData>[];

    if (nextEvent != null) {
      final d = nextEvent.date;
      final dateLabel =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      alerts.add(
        FamilyAlertData(
          tag: _typeLabels[nextEvent.type] ?? 'AGENDA',
          title: nextEvent.title,
          subtitle: nextEvent.location.isNotEmpty
              ? '$dateLabel · ${nextEvent.location}'
              : dateLabel,
          bgColor: SaluteColors.primaryGreen,
          icon: _typeIcons[nextEvent.type] ?? Icons.event_note_outlined,
        ),
      );
    }

    final endingSoon = medications.where((m) => m.isEndingSoon).take(2);
    for (final m in endingSoon) {
      alerts.add(
        FamilyAlertData(
          tag: 'MEDICACIÓN',
          title: '${m.name} está por terminar',
          subtitle: 'Quedan ${m.daysRemaining} día(s) de tratamiento',
          bgColor: SaluteColors.terracotta,
          icon: Icons.medication_liquid_outlined,
        ),
      );
    }

    return alerts;
  }

  List<MedicationData> _buildMedications(List<Medication> medications) {
    return medications
        .map(
          (m) => MedicationData(
            id: m.id,
            name: m.name,
            dose: m.timesOfDay.isNotEmpty ? _formatTimes(m.timesOfDay) : m.dose,
            progress: m.progress,
            isChronic: m.isChronic,
          ),
        )
        .toList();
  }

  /// Misma regla que `canSeeClinicalData` en firestore.rules: la persona
  /// que administra el perfil, o alguien con quien se compartió.
  bool get _canSeeClinical {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    return profile.ownerUid == uid || profile.sharedWithUids.contains(uid);
  }

  /// El contacto SOS (el que se carga en el Diario) es un dato de la CUENTA
  /// (`users/{uid}`), no del perfil. Es "el contacto de emergencia de esta
  /// ficha" cuando la ficha es del propio usuario o de un dependiente suyo
  /// (misma regla que la ficha médica); en el perfil de otro familiar con
  /// cuenta propia no se puede leer ni corresponde.
  bool get _sosApplies {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Una mascota no tiene contacto de emergencia: el SOS de la cuenta es
    // de una persona (su dueño), así que ni se lee para ese perfil.
    return uid != null &&
        profile.ownerUid == uid &&
        profile.type == ProfileType.persona &&
        (profile.isSelf || profile.isDependent);
  }

  /// "Mamá · 351 123 4567", o null si no hay contacto SOS configurado
  /// (en ese caso queda lo que diga el propio perfil).
  String? _sosLabel(SosContact? sos) {
    if (sos == null) return null;
    final phone = sos.phoneNumber.trim();
    return phone.isEmpty ? sos.displayName : '${sos.displayName} · $phone';
  }

  /// Un solo dato, el más relevante del último registro (entra en el chip).
  /// Resumen de la tarjeta de una mascota: su último peso registrado (si no
  /// hay registros, el de la ficha). Ignora el resto de las métricas.
  String _petWeightSummary(List<VitalEntry> vitals) {
    for (final v in vitals) {
      if (v.weightKg != null) return formatPetWeightKg(v.weightKg!);
    }
    final w = profile.weightKg;
    return w != null ? formatPetWeightKg(w) : 'Sin datos aún';
  }

  String _wellbeingSummary(VitalEntry? e) {
    if (e == null) return 'Sin datos aún';
    if (e.heartRate != null) return '${e.heartRate} bpm';
    if (e.sleepHours != null)
      return '${e.sleepHours!.toStringAsFixed(1)} h sueño';
    if (e.weightKg != null) return '${e.weightKg!.toStringAsFixed(1)} kg';
    if (e.steps != null) return '${e.steps} pasos';
    if (e.stressLevel != null) return 'Estrés ${e.stressLevel!.name}';
    return 'Sin datos aún';
  }

  @override
  Widget build(BuildContext context) {
    // Sin consentimiento NO se abre ningún stream clínico: Firestore
    // rechazaría la consulta (permission-denied) y además no corresponde
    // mostrar datos de salud de alguien que no los compartió.
    if (!_canSeeClinical)
      return _LockedProfileView(profile: profile, onBack: onBackToDashboard);

    if (!_sosApplies) return _buildLive(context, null);
    return StreamBuilder<SosContact?>(
      stream: SosContactService.instance.watchSosContact(),
      builder: (context, sosSnap) => _buildLive(context, sosSnap.data),
    );
  }

  Widget _buildLive(BuildContext context, SosContact? sos) {
    return StreamBuilder<List<Medication>>(
      stream: MedicationService.instance.watchMedications(profile.id),
      builder: (context, medSnap) {
        final medications = medSnap.data ?? const <Medication>[];
        return StreamBuilder<AgendaEvent?>(
          stream: AgendaService.instance.watchNextForProfile(profile.id),
          builder: (context, agendaSnap) {
            final nextEvent = agendaSnap.data;
            return StreamBuilder<List<VitalEntry>>(
              stream: VitalsService.instance.watchForProfile(profile.id),
              builder: (context, vitalsSnap) {
                final vitals = vitalsSnap.data ?? const <VitalEntry>[];
                final baseData = profile.toDisplayData();
                final member = baseData.copyWith(
                  alerts: _buildAlerts(nextEvent, medications),
                  medications: _buildMedications(medications),
                  latestVital: profile.type == ProfileType.mascota
                      ? null
                      : (vitals.isEmpty ? null : vitals.first),
                  wellbeingValue: profile.type == ProfileType.mascota
                      ? _petWeightSummary(vitals)
                      : _wellbeingSummary(vitals.isEmpty ? null : vitals.first),
                  emergencyContact: _sosLabel(sos),
                  emergencyName: sos?.displayName,
                  emergencyPhone: sos?.phoneNumber,
                );

                return FamiliarProfileScreen(
                  member: member,
                  onEdit: onEdit,
                  onBackToDashboard: onBackToDashboard,
                  onChangePhoto: _canEditPhoto
                      ? () => _changePhoto(context)
                      : null,
                  // Mismo comportamiento que el Protocolo de Emergencia del
                  // Diario: tocar el contacto llama; el lápiz lo cambia.
                  onCallEmergency:
                      sos != null && sos.phoneNumber.trim().isNotEmpty
                      ? () => SosActions.call(context, sos)
                      : null,
                  onEditEmergency: _sosApplies
                      ? () => SosActions.pickAndSave(context)
                      : null,
                  onQuickRecord: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MedicalSheetScreen(
                          profileId: profile.id,
                          profileName: profile.name,
                        ),
                      ),
                    );
                  },
                  // Carné de vacunación: mascotas (esquema perro/gato) y
                  // personas (Calendario Nacional según la edad).
                  onOpenVaccines: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VaccineCardScreen(profile: profile),
                      ),
                    );
                  },
                  // Una mascota no tiene bio-métricas (sueño, pasos, estrés):
                  // la tarjeta abre su historial de peso.
                  onOpenWellbeing: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => profile.type == ProfileType.mascota
                            ? PetWeightScreen(profile: profile)
                            : BiometricsScreen(
                                profileId: profile.id,
                                profileName: profile.name,
                              ),
                      ),
                    );
                  },
                  onEditMedication: (medicationId) {
                    Medication? existing;
                    for (final m in medications) {
                      if (m.id == medicationId) {
                        existing = m;
                        break;
                      }
                    }
                    if (existing == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MedicationFormScreen(
                          profileId: profile.id,
                          profileName: profile.name,
                          existingMedication: existing,
                        ),
                      ),
                    );
                  },
                  onOpenChecklist: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            MedicationChecklistScreen(profile: profile),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Lo que ve alguien de la familia que NO tiene permiso sobre este perfil:
/// solo quién es, sin ningún dato de salud.
class _LockedProfileView extends StatelessWidget {
  final FamilyProfile profile;
  final VoidCallback? onBack;
  const _LockedProfileView({required this.profile, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Perfil',
              onBack: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProfileAvatar.fromProfile(profile, radius: 48),
                      const SizedBox(height: 16),
                      Text(
                        profile.fullName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Icon(
                        Icons.lock_outline,
                        size: 36,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Este perfil no compartió su información de salud con vos.\n'
                        'Quien lo administra puede darte acceso desde Familia.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
