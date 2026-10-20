import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/profile/medication_checklist_screen.dart';
import 'package:saluteapp/profile/medication_form_screen.dart';

/// Plan de tratamientos del perfil. La edición y el alta siguen usando
/// [MedicationFormScreen], por lo que se conservan alertas, botiquín y
/// horarios existentes.
class TreatmentsScreen extends StatelessWidget {
  final FamilyProfile profile;

  const TreatmentsScreen({super.key, required this.profile});

  Future<void> _openForm(BuildContext context, [Medication? medication]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MedicationFormScreen(
          profileId: profile.id,
          profileName: profile.name,
          existingMedication: medication,
        ),
      ),
    );
  }

  void _openChecklist(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MedicationChecklistScreen(profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: SaluteColors.primaryGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo tratamiento'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Tratamientos',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: StreamBuilder<List<Medication>>(
                stream: MedicationService.instance.watchMedications(
                  profile.id,
                  onlyActive: false,
                  decryptNotes: false,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _Message(
                      text:
                          'No se pudieron cargar los tratamientos.\n${snapshot.error}',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: SaluteColors.primaryGreen,
                      ),
                    );
                  }

                  final medications = snapshot.data!;
                  final active = medications
                      .where((m) => m.active && !m.hasEnded)
                      .toList();
                  final history = medications
                      .where((m) => !m.active || m.hasEnded)
                      .toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => _openChecklist(context),
                          icon: const Icon(Icons.checklist_outlined, size: 18),
                          label: const Text('Ver tomas de hoy'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SaluteColors.primaryGreen,
                            side: BorderSide(
                              color: SaluteColors.primaryGreen.withValues(
                                alpha: .35,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Intro(profileName: profile.name),
                      const SizedBox(height: 18),
                      _SummaryCard(active: active),
                      const SizedBox(height: 24),
                      _SectionLabel(
                        title: 'Tratamientos activos',
                        count: active.length,
                      ),
                      const SizedBox(height: 10),
                      if (active.isEmpty)
                        const _EmptyCard()
                      else
                        ...active.map(
                          (medication) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TreatmentCard(
                              medication: medication,
                              onEdit: () => _openForm(context, medication),
                              onTake: () => _openChecklist(context),
                            ),
                          ),
                        ),
                      if (history.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SectionLabel(
                          title: 'Historial',
                          count: history.length,
                        ),
                        const SizedBox(height: 10),
                        ...history.map(
                          (medication) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _HistoryCard(
                              medication: medication,
                              onEdit: () => _openForm(context, medication),
                            ),
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

class _Intro extends StatelessWidget {
  final String profileName;
  const _Intro({required this.profileName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: SaluteColors.lightGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'SUPERVISIÓN CLÍNICA ACTIVA',
            style: TextStyle(
              color: SaluteColors.primaryGreen,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tratamientos prescritos',
          style: TextStyle(
            color: SaluteColors.darkGreen,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Cronograma terapéutico personalizado para $profileName, '
          'sincronizado con el botiquín y las alertas.',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<Medication> active;
  const _SummaryCard({required this.active});

  @override
  Widget build(BuildContext context) {
    final scheduled = active.where((m) => m.timesOfDay.isNotEmpty).length;
    final next = _nextTime(active);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _SummaryItem(value: '${active.length}', label: 'ACTIVOS'),
          _SummaryItem(value: next ?? '—', label: 'PRÓXIMA'),
          _SummaryItem(
            value: scheduled == active.length && active.isNotEmpty
                ? '100%'
                : '—',
            label: 'ADHERENCIA',
          ),
        ],
      ),
    );
  }

  String? _nextTime(List<Medication> medications) {
    final now = TimeOfDay.now();
    final current = now.hour * 60 + now.minute;
    final times =
        medications
            .expand((m) => m.timesOfDay)
            .map(parseTimeOfDay)
            .whereType<(int, int)>()
            .map((t) => t.$1 * 60 + t.$2)
            .where((minutes) => minutes >= current)
            .toList()
          ..sort();
    if (times.isEmpty) return null;
    final minutes = times.first;
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  }
}

class _SummaryItem extends StatelessWidget {
  final String value;
  final String label;
  const _SummaryItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: SaluteColors.primaryGreen,
              fontSize: DsFontSize.xxl,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final int count;
  const _SectionLabel({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: DsFontSize.xl,
            fontWeight: DsFontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 11,
          backgroundColor: SaluteColors.lightGreen,
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              color: SaluteColors.primaryGreen,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _TreatmentCard extends StatelessWidget {
  final Medication medication;
  final VoidCallback onEdit;
  final VoidCallback onTake;
  const _TreatmentCard({
    required this.medication,
    required this.onEdit,
    required this.onTake,
  });

  @override
  Widget build(BuildContext context) {
    final duration = medication.isChronic
        ? 'CRÓNICO / SIN FECHA DE FIN'
        : 'TRATAMIENTO TEMPORAL · DÍA ${(medication.progress * medication.durationDays!).ceil()} DE ${medication.durationDays}';
    final times = medication.timesOfDay.isEmpty
        ? 'Según indicación'
        : medication.timesOfDay.join('  ·  ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Tag(label: duration, color: SaluteColors.lightGreen),
              if (medication.remindersEnabled)
                _Tag(label: 'ALERTAS ACTIVAS', color: SaluteColors.lightGreen),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  medication.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: SaluteColors.darkGreen,
                  ),
                ),
              ),
              _Tag(label: medication.dose, color: SaluteColors.bgColor),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            medication.notes.isEmpty
                ? 'Tratamiento indicado por tu profesional de salud.'
                : medication.notes,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade600,
              height: 1.3,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SaluteColors.bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  size: 17,
                  color: SaluteColors.darkGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    times,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.medical_services_outlined,
                size: 16,
                color: SaluteColors.darkGreen,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  medication.botiquinItemId == null
                      ? 'Sin vincular al botiquín'
                      : 'Vinculado al botiquín',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Ajustar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onTake,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Registrar toma'),
                  style: FilledButton.styleFrom(
                    backgroundColor: SaluteColors.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Medication medication;
  final VoidCallback onEdit;
  const _HistoryCard({required this.medication, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      leading: const Icon(Icons.history, color: SaluteColors.darkGreen),
      title: Text(
        medication.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        medication.hasEnded ? 'Tratamiento finalizado' : 'Tratamiento pausado',
      ),
      trailing: IconButton(
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: SaluteColors.primaryGreen,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.medication_outlined,
            color: SaluteColors.primaryGreen,
            size: 34,
          ),
          SizedBox(height: 8),
          Text(
            'Todavía no hay tratamientos activos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'Usá “Nuevo tratamiento” para agregar el primero.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
