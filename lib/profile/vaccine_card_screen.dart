import 'package:saluteapp/components/a11y_tap.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/vaccine_record.dart';
import 'package:saluteapp/core/services/attachment_service.dart';
import 'package:saluteapp/core/services/person_vaccine_catalog.dart';
import 'package:saluteapp/core/services/vaccine_catalog.dart';
import 'package:saluteapp/core/services/vaccine_service.dart';
import 'package:saluteapp/profile/vaccine_form_screen.dart';
import 'package:saluteapp/profile/vaccine_scan_screen.dart';
import 'package:saluteapp/profile/vaccine_widgets.dart';

/// Carné de vacunación de una mascota O de una persona (`profiles/{id}/vacunas`).
///
/// Dos fuentes que NO se mezclan:
///  - el CALENDARIO (plantilla de perro/gato, o el Calendario Nacional de
///    Argentina para personas según la edad; siempre orientativo) dice qué
///    debería corresponder;
///  - el HISTORIAL son las dosis que el usuario cargó de verdad.
/// La pantalla las compara y muestra el estado de cada vacuna; lo que no
/// está registrado figura como "Sin registro", nunca como "omitida".
class VaccineCardScreen extends StatefulWidget {
  final FamilyProfile profile;
  const VaccineCardScreen({super.key, required this.profile});

  @override
  State<VaccineCardScreen> createState() => _VaccineCardScreenState();
}

class _VaccineCardScreenState extends State<VaccineCardScreen> {
  late Future<List<VaccineRecord>> _future;

  FamilyProfile get _profile => widget.profile;

  bool get _isPet => _profile.type == ProfileType.mascota;

  /// Solo quien administra el perfil escribe (ver reglas de `vacunas`).
  bool get _canEdit => _profile.ownerUid == FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _future = VaccineService.instance.fetch(_profile.id);
  }

  void _reload() {
    setState(() => _future = VaccineService.instance.fetch(_profile.id));
  }

  void _msg(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openForm({
    VaccineRecord? existing,
    VaccineDraft? draft,
    required List<VaccineRecord> all,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VaccineFormScreen(
          profile: _profile,
          existing: existing,
          draft: draft,
          existingRecords: all,
        ),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _openScan(List<VaccineRecord> all) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VaccineScanScreen(profile: _profile, existingRecords: all),
      ),
    );
    if (saved == true) _reload();
  }

  void _showAddSheet(List<VaccineRecord> all) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Agregar al carné', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: SaluteColors.lightGreen,
                  child: Icon(Icons.document_scanner_outlined, color: SaluteColors.primaryGreen),
                ),
                title: const Text('Escanear certificado', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Foto de la libreta: leemos las vacunas y vos las revisás.'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openScan(all);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: SaluteColors.lightGreen,
                  child: Icon(Icons.edit_outlined, color: SaluteColors.primaryGreen),
                ),
                title: const Text('Cargar a mano', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Una dosis por vez.'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openForm(all: all);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(VaccineRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar vacuna'),
        content: Text(
          '¿Eliminar "${r.name}" del ${fmtVaccineDate(r.date)}? '
          '${r.agendaEventId != null ? 'También se quita su recordatorio. ' : ''}'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: SaluteColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await VaccineService.instance.delete(_profile.id, r);
      _reload();
    } catch (e) {
      if (mounted) _msg('No se pudo eliminar: $e');
    }
  }

  Future<void> _openAttachment(VaccineRecord r) async {
    final att = r.attachment;
    if (att == null) return;
    final ok = await AttachmentService.instance.open(att);
    if (!ok && mounted) {
      _msg('No se pudo abrir el archivo. Puede haberse cargado desde otro dispositivo.');
    }
  }

  Future<void> _shareAttachment(VaccineRecord r) async {
    final att = r.attachment;
    if (att == null) return;
    final ok = await AttachmentService.instance.share(att, text: 'Vacuna ${r.name} · ${_profile.name}');
    if (!ok && mounted) _msg('El archivo no está disponible en este dispositivo.');
  }

  void _showDetails(VaccineRecord r, List<VaccineRecord> all) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                r.source == VaccineSource.ocr
                    ? 'Leída del certificado y confirmada'
                    : 'Cargada a mano',
                style: TextStyle(color: SaluteColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _DetailRow(icon: Icons.event_available_outlined, label: 'Aplicada', value: fmtVaccineDate(r.date)),
              if (r.nextDoseDate != null)
                _DetailRow(icon: Icons.event_repeat_outlined, label: 'Próxima dosis', value: fmtVaccineDate(r.nextDoseDate!)),
              if (r.professional.isNotEmpty)
                _DetailRow(
                  icon: Icons.medical_services_outlined,
                  label: _isPet ? 'Veterinario' : 'Profesional',
                  value: r.professional,
                ),
              if (r.lot.isNotEmpty) _DetailRow(icon: Icons.tag, label: 'Lote', value: r.lot),
              if (r.notes.isNotEmpty) _DetailRow(icon: Icons.notes_outlined, label: 'Notas', value: r.notes),
              if (r.attachment != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openAttachment(r),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Ver certificado'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _shareAttachment(r),
                        icon: const Icon(Icons.share_outlined, size: 18),
                        label: const Text('Compartir'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_canEdit) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _openForm(existing: r, all: all);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SaluteColors.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _delete(r);
                        },
                        style: OutlinedButton.styleFrom(foregroundColor: SaluteColors.danger),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Eliminar'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Qué cubre una vacuna y a qué edades se aplica (solo personas).
  void _showSlotInfo(VaccineSlot slot) {
    final t = slot.template;
    if (t == null) return;
    final doses = t.doseMonthsFor?.call(_profile.birthDate, DateTime.now()) ?? t.doseMonths;
    final repeat = t.repeatEveryDays;
    String? schedule;
    if (doses.isNotEmpty) {
      schedule = 'Dosis: ${doses.map(PersonVaccines.doseAgeLabel).join(' · ')}.';
    } else if (repeat != null) {
      schedule = repeat >= 3650 ? 'Refuerzo cada 10 años.' : 'Refuerzo todos los años.';
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(t.covers, style: const TextStyle(fontSize: 14, height: 1.4)),
              if (schedule != null) ...[
                const SizedBox(height: 10),
                Text(schedule, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
              if (t.optional) ...[
                const SizedBox(height: 10),
                Text(
                  'Es opcional o depende del riesgo: solo figura como faltante si la cargás.',
                  style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'Guía orientativa del Calendario Nacional. Tu médico indica qué corresponde en cada caso.',
                style: TextStyle(fontSize: 12, color: SaluteColors.textMuted, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSlotTap(VaccineSlot slot, List<VaccineRecord> all) {
    if (!_canEdit) return;
    switch (slot.status) {
      case VaccineStatus.noCorresponde:
        _msg(
          '${slot.name} todavía no corresponde por la edad de ${_profile.name}. '
          'Consultalo con ${_isPet ? 'tu veterinario' : 'tu médico o pediatra'}.',
        );
      case VaccineStatus.verificar:
        // Datos contradictorios: se abre la última dosis para corregirla.
        if (slot.latest != null) _openForm(existing: slot.latest, all: all);
      default:
        // Registrar una dosis (nueva) de esta vacuna.
        // Personas: siempre el nombre de la plantilla (una dTpa reciente cuenta
        // como dT, pero la dosis nueva que se carga desde esta fila es de dT).
        final hasSuggestion = slot.template?.suggestions.isNotEmpty == true;
        final name = hasSuggestion && (!_isPet || slot.latest == null)
            ? slot.template!.suggestions.first
            : (slot.latest?.name ?? slot.name);
        _openForm(draft: VaccineDraft(name: name), all: all);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader.secondary(title: 'Carné de vacunas'),
            Expanded(
              child: FutureBuilder<List<VaccineRecord>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: SaluteColors.primaryGreen));
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: SaluteColors.terracotta, size: 36),
                            const SizedBox(height: 12),
                            Text('No se pudo cargar el carné.\n${snap.error}', textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _reload, child: const Text('Reintentar')),
                          ],
                        ),
                      ),
                    );
                  }
                  return _buildContent(snap.data ?? const []);
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: !_canEdit
          ? null
          : FutureBuilder<List<VaccineRecord>>(
              future: _future,
              builder: (context, snap) => FloatingActionButton.extended(
                onPressed: snap.hasData ? () => _showAddSheet(snap.data!) : null,
                backgroundColor: SaluteColors.primaryGreen,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Agregar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
    );
  }

  Widget _buildContent(List<VaccineRecord> records) {
    final birth = _profile.birthDate;
    final List<VaccineSlot> slots;
    final String schemeHelp;
    if (_isPet) {
      final species = petSpeciesFrom(_profile.species);
      slots = VaccineCatalog.evaluate(
        species: species,
        birthDate: birth,
        records: records,
      );
      schemeHelp = species == PetSpecies.otro
          ? 'Para esta especie no hay un esquema sugerido: cargá las vacunas que te indique el veterinario.'
          : 'Esquema orientativo para ${species == PetSpecies.perro ? 'perros' : 'gatos'}. '
              'Tu veterinario define qué dosis y cuándo, según la edad y el riesgo de ${_profile.name}.';
    } else {
      slots = PersonVaccines.evaluate(birthDate: birth, records: records);
      schemeHelp = 'Basado en el Calendario Nacional de Vacunación de Argentina (2026). Es orientativo: '
          'tu médico o pediatra indica qué corresponde según los antecedentes, el embarazo, '
          'los factores de riesgo y la zona donde vive ${_profile.name}.';
    }
    int count(VaccineStatus s) => slots.where((x) => x.status == s).length;

    final ageMonths = birth == null ? null : PersonVaccines.monthsBetween(birth, DateTime.now());
    final showPregnancyNote = !_isPet && ageMonths != null && ageMonths >= 144 && ageMonths <= 600;
    final helpStyle = TextStyle(fontSize: 12, color: SaluteColors.textMuted, height: 1.35);

    return RefreshIndicator(
      color: SaluteColors.primaryGreen,
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          _ProfileHeader(profile: _profile, isPet: _isPet),
          const SizedBox(height: 16),
          if (!_isPet && birth == null) ...[
            _Notice(
              icon: Icons.cake_outlined,
              text: 'Falta la fecha de nacimiento de ${_profile.name}. Cargala en su perfil para ver '
                  'qué vacunas corresponden por edad. Mientras tanto se muestran solo las dosis cargadas.',
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              _CountBox(label: 'PRÓXIMAS', value: count(VaccineStatus.proxima), color: SaluteColors.darkGreen),
              const SizedBox(width: 10),
              _CountBox(label: 'PENDIENTES', value: count(VaccineStatus.pendiente), color: SaluteColors.brownOrange),
              const SizedBox(width: 10),
              _CountBox(label: 'SIN REGISTRO', value: count(VaccineStatus.sinRegistro), color: SaluteColors.textMuted),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionLabel('Esquema'),
          const SizedBox(height: 4),
          Text(schemeHelp, style: helpStyle),
          if (showPregnancyNote) ...[
            const SizedBox(height: 6),
            Text(
              'En un embarazo el calendario suma dTpa (desde la semana 20), antigripal y VSR '
              '(semanas 32 a 36.6) en cada gestación. Podés cargarlas con "Agregar".',
              style: helpStyle,
            ),
          ],
          const SizedBox(height: 12),
          if (slots.isEmpty)
            const _Empty(text: 'Todavía no cargaste ninguna vacuna.')
          else
            for (final s in slots) ...[
              _SlotTile(
                slot: s,
                isPet: _isPet,
                onTap: _canEdit ? () => _onSlotTap(s, records) : null,
                onInfo: !_isPet && s.template != null ? () => _showSlotInfo(s) : null,
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 14),
          const _SectionLabel('Historial'),
          const SizedBox(height: 12),
          if (records.isEmpty)
            const _Empty(text: 'Acá van a aparecer las dosis aplicadas.')
          else
            for (final r in records) ...[
              _RecordTile(record: r, onTap: () => _showDetails(r, records)),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final FamilyProfile profile;
  final bool isPet;
  const _ProfileHeader({required this.profile, required this.isPet});

  @override
  Widget build(BuildContext context) {
    final birth = profile.birthDate;
    final sub = isPet
        ? [
            if ((profile.species ?? '').isNotEmpty) profile.species!,
            if ((profile.breed ?? '').isNotEmpty) profile.breed!,
          ].join(' · ')
        : [
            if (birth != null) PersonVaccines.ageLabel(birth, DateTime.now()),
            if (!profile.isSelf && profile.relation.isNotEmpty) profile.relation,
          ].join(' · ');
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: isPet ? SaluteColors.terracotta : SaluteColors.darkGreen,
          child: Icon(isPet ? Icons.pets_outlined : Icons.person_outline, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 13, color: SaluteColors.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SaluteColors.brownOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SaluteColors.brownOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: SaluteColors.brownOrange),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35))),
        ],
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _CountBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SaluteColors.textMuted)),
            const SizedBox(height: 6),
            Text('$value', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SaluteColors.textMuted, letterSpacing: 0.6),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(text, style: TextStyle(color: SaluteColors.textMuted, fontWeight: FontWeight.w600)),
        ),
      );
}

class _SlotTile extends StatelessWidget {
  final VaccineSlot slot;
  final bool isPet;
  final VoidCallback? onTap;

  /// Abre "qué cubre esta vacuna" (solo personas).
  final VoidCallback? onInfo;
  const _SlotTile({required this.slot, required this.isPet, this.onTap, this.onInfo});

  String _petSubtitle() {
    final r = slot.latest;
    switch (slot.status) {
      case VaccineStatus.sinRegistro:
        return 'No hay dosis cargadas. Si ya la tiene, cargala desde el certificado.';
      case VaccineStatus.noCorresponde:
        return 'Todavía no corresponde por la edad.';
      case VaccineStatus.verificar:
        return 'Las fechas no cierran. Revisá la última dosis o consultá al veterinario.';
      case VaccineStatus.pendiente:
        return 'Se indicó para el ${fmtVaccineDate(r!.nextDoseDate!)}. Todavía no hay una dosis nueva registrada.';
      case VaccineStatus.proxima:
        return 'Próxima dosis: ${fmtVaccineDate(r!.nextDoseDate!)}.';
      case VaccineStatus.aplicada:
        return 'Última dosis: ${fmtVaccineDate(r!.date)}.';
    }
  }

  String _personSubtitle() {
    final r = slot.latest;
    final due = slot.nextDue;
    final recurring = slot.template?.repeatEveryDays != null;
    final total = slot.dosesTotal ?? 0;
    final progress = total > 1 ? '${slot.dosesDone} de $total dosis. ' : '';
    switch (slot.status) {
      case VaccineStatus.sinRegistro:
        return 'No hay dosis cargadas. Si ya la recibió, cargala desde la libreta o el certificado.';
      case VaccineStatus.noCorresponde:
        return due == null
            ? 'Todavía no corresponde por la edad.'
            : 'Todavía no corresponde: desde el ${fmtVaccineDate(due)}.';
      case VaccineStatus.verificar:
        return 'Las fechas no cierran. Revisá la última dosis o consultá a tu médico.';
      case VaccineStatus.pendiente:
        if (due == null && r?.nextDoseDate != null) {
          return 'Se indicó para el ${fmtVaccineDate(r!.nextDoseDate!)}. Todavía no hay una dosis nueva registrada.';
        }
        if (due == null) return '${progress}Según el calendario corresponde una dosis más.';
        return recurring
            ? 'Refuerzo vencido desde el ${fmtVaccineDate(due)}.'
            : '${progress}Según el calendario ya corresponde la siguiente dosis (desde el ${fmtVaccineDate(due)}).';
      case VaccineStatus.proxima:
        final next = due ?? r?.nextDoseDate;
        return next == null
            ? '${progress}Hay una próxima dosis por aplicar.'
            : '${progress}Próxima dosis: ${fmtVaccineDate(next)}.';
      case VaccineStatus.aplicada:
        final complete = total > 0 && slot.dosesDone >= total;
        final last = r == null ? '' : 'Última dosis: ${fmtVaccineDate(r.date)}.';
        final nextBoost = recurring && due != null ? ' Próximo refuerzo: ${fmtVaccineDate(due)}.' : '';
        return '${complete ? 'Esquema completo. ' : progress}$last$nextBoost';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: vaccineStatusColor(slot.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.vaccines_outlined, color: vaccineStatusColor(slot.status), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(slot.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                      if (onInfo != null)
                        A11yTap(
                          label: 'Más información sobre ${slot.name}',
                          onTap: onInfo,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.info_outline, size: 16, color: SaluteColors.textMuted),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isPet ? _petSubtitle() : _personSubtitle(),
                    style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Tope de ancho: con textos grandes el chip baja de línea en vez de
            // empujar el nombre fuera de la tarjeta.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.36),
              child: VaccineStatusChip(slot.status),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final VaccineRecord record;
  final VoidCallback onTap;
  const _RecordTile({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = record;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      fmtVaccineDate(r.date),
                      if (r.nextDoseDate != null) 'próxima ${fmtVaccineDate(r.nextDoseDate!)}',
                      if (r.professional.isNotEmpty) r.professional,
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            if (r.attachment != null)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.attach_file_rounded, size: 18, color: SaluteColors.primaryGreen),
              ),
            Icon(Icons.chevron_right, color: SaluteColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: SaluteColors.primaryGreen),
          const SizedBox(width: 10),
          Text('$label: ', style: TextStyle(fontSize: 13, color: SaluteColors.textMuted, fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
