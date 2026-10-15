import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/services/medical_record_service.dart';
import 'package:saluteapp/profile/consulta_form_screen.dart';

const _monthAbbr = [
  'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
];

/// Consultas (`RecordCategory.consulta`) de UN perfil, con alta, edición y
/// borrado. Es lo que alimenta "Historial médico reciente" de la ficha
/// (veterinaria o médica): sin consultas cargadas, ese bloque queda casi vacío.
///
/// Solo quien administra el perfil puede escribir (reglas de Firestore);
/// quien lo ve por acceso compartido solo lee, así que ahí se ocultan los
/// controles de alta/edición/borrado.
class ConsultasScreen extends StatefulWidget {
  final FamilyProfile profile;
  const ConsultasScreen({super.key, required this.profile});

  @override
  State<ConsultasScreen> createState() => _ConsultasScreenState();
}

class _ConsultasScreenState extends State<ConsultasScreen> {
  late Future<List<MedicalRecord>> _future;

  FamilyProfile get _profile => widget.profile;
  bool get _isPet => _profile.type == ProfileType.mascota;
  bool get _canEdit => _profile.ownerUid == FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<MedicalRecord>> _fetch() async {
    final records = await MedicalRecordService.instance.fetchRecords(_profile.id, limit: 100);
    return records.where((r) => r.category == RecordCategory.consulta).toList();
  }

  void _reload() {
    setState(() => _future = _fetch());
  }

  Future<void> _openForm({MedicalRecord? record}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ConsultaFormScreen(
          profileId: _profile.id,
          profileName: _profile.name,
          isPet: _isPet,
          record: record,
        ),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(MedicalRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar consulta?'),
        content: Text('Se va a borrar "${r.title}". No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: SaluteColors.terracotta)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MedicalRecordService.instance.deleteRecord(_profile.id, r.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la consulta: $e')),
      );
    }
  }

  void _showDetails(MedicalRecord r) {
    final diagnosis = (r.details[kConsultaDiagnosisKey] as String?)?.trim() ?? '';
    final treatment = (r.details[kConsultaTreatmentKey] as String?)?.trim() ?? '';
    final notes = (r.details[kConsultaNotesKey] as String?)?.trim() ?? '';
    final proLabel = _isPet ? 'Veterinario/a' : 'Médico/a';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${_profile.name} · ${_fmtFull(r.date)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (r.professional.isNotEmpty) _DetailRow(label: proLabel, value: r.professional),
                if (r.institution.isNotEmpty) _DetailRow(label: 'Lugar', value: r.institution),
                if (diagnosis.isNotEmpty) _DetailRow(label: 'Diagnóstico', value: diagnosis),
                if (treatment.isNotEmpty) _DetailRow(label: 'Indicaciones', value: treatment),
                if (notes.isNotEmpty) _DetailRow(label: 'Notas', value: notes),
                if (diagnosis.isEmpty && treatment.isEmpty && notes.isEmpty)
                  const Text(
                    'Sin diagnóstico ni indicaciones cargados.',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                if (_canEdit) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _openForm(record: r);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Editar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _delete(r);
                          },
                          style: OutlinedButton.styleFrom(foregroundColor: SaluteColors.terracotta),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              onPressed: () => _openForm(),
              backgroundColor: SaluteColors.primaryGreen,
              tooltip: 'Nueva consulta',
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: 'Consultas · ${_profile.name}'),
            Expanded(
              child: FutureBuilder<List<MedicalRecord>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: SaluteColors.primaryGreen));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No se pudieron cargar las consultas.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(onPressed: _reload, child: const Text('Reintentar')),
                          ],
                        ),
                      ),
                    );
                  }
                  final items = snapshot.data ?? const <MedicalRecord>[];
                  if (items.isEmpty) return _EmptyState(isPet: _isPet, canEdit: _canEdit);
                  return RefreshIndicator(
                    color: SaluteColors.primaryGreen,
                    onRefresh: () async => _reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ConsultaCard(record: items[i], onTap: () => _showDetails(items[i])),
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

String _fmtFull(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _ConsultaCard extends StatelessWidget {
  final MedicalRecord record;
  final VoidCallback onTap;
  const _ConsultaCard({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final who = [record.professional, record.institution].where((s) => s.trim().isNotEmpty).join(' · ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: SaluteColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      record.date.day.toString().padLeft(2, '0'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SaluteColors.primaryGreen),
                    ),
                    Text(
                      _monthAbbr[record.date.month - 1],
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SaluteColors.primaryGreen),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (who.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, height: 1.3)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isPet;
  final bool canEdit;
  const _EmptyState({required this.isPet, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isPet ? Icons.pets_outlined : Icons.medical_services_outlined, size: 44, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('Todavía no hay consultas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              canEdit
                  ? 'Registrá las visitas ${isPet ? 'al veterinario' : 'al médico'} con el botón +. '
                      'Van a aparecer en el historial de la ficha.'
                  : 'Quien administra este perfil todavía no cargó consultas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
