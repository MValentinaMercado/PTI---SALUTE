import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/services/attachment_service.dart';
import 'package:saluteapp/core/services/medical_record_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/profile/order_form_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// "Órdenes" = estudios / análisis / imágenes del historial médico familiar.
// Técnicamente son MedicalRecord (misma infraestructura que Triaje/Ánimo,
// ver core/models/medical_record.dart), acotados a las categorías que
// tienen sentido como "orden médica": estudio, laboratorio, cardiología.
// Consulta (ver consultas_screen.dart), vacuna, odontología, psicología,
// triaje y ánimo tienen su propia pantalla de carga; no se listan acá para
// no duplicar.
// ─────────────────────────────────────────────────────────────────────────────

const _orderCategories = [RecordCategory.estudio, RecordCategory.laboratorio, RecordCategory.cardiologia];

const _categoryLabels = {
  RecordCategory.estudio: 'Estudio',
  RecordCategory.laboratorio: 'Laboratorio',
  RecordCategory.cardiologia: 'Cardiología',
};

const _categoryIcons = {
  RecordCategory.estudio: Icons.description_outlined,
  RecordCategory.laboratorio: Icons.science_outlined,
  RecordCategory.cardiologia: Icons.monitor_heart_outlined,
};

const _categoryColors = {
  RecordCategory.estudio: SaluteColors.darkGreen,
  RecordCategory.laboratorio: SaluteColors.primaryGreen,
  RecordCategory.cardiologia: SaluteColors.terracotta,
};

const _monthAbbr = [
  'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
];

String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_monthAbbr[d.month - 1]}';

/// Una orden con el nombre del perfil dueño ya resuelto (MedicalRecord no
/// lo denormaliza, a diferencia de AgendaEvent), para no tener que
/// joinear en cada card.
class _OrderEntry {
  final MedicalRecord record;
  final String profileId;
  final String profileName;
  const _OrderEntry({required this.record, required this.profileId, required this.profileName});
}

/// Recorre los perfiles de la familia y trae, de cada uno, las entradas
/// de su historial que sean de tipo "orden" (ver `_orderCategories`).
/// Mismo patrón que `_fetchLatestTriage` en diario.dart: son pocos
/// perfiles, así que traer todo y filtrar en memoria es suficiente.
///
/// Con [only] trae solo las órdenes de ese perfil (ej. desde el Diario de
/// una mascota); sin él, las de todos los perfiles visibles.
Future<List<_OrderEntry>> _fetchOrders({FamilyProfile? only}) async {
  final myUid = FirebaseAuth.instance.currentUser?.uid;
  final profiles = await ProfileService.instance.watchProfiles().first;

  // BUGFIX: watchProfiles() trae TODOS los perfiles de la familia
  // (regla `profiles`: alcanza con compartir familyId), pero
  // `profiles/{id}/historial` exige consentimiento clínico explícito
  // (`canSeeClinicalData`: administrás el perfil o estás en
  // `sharedWithUids`). Antes se pedía el historial de cada perfil de
  // la familia sin filtrar, y en cuanto tocaba uno sin consentimiento,
  // el `permission-denied` de ESE perfil tiraba abajo el `Future`
  // entero (no había try/catch en el loop), rompiendo toda la
  // pantalla de Órdenes. Ahora filtramos antes de pedir nada.
  final candidates = only != null ? [only] : profiles;
  final visible = candidates.where(
        (p) => myUid != null && (p.ownerUid == myUid || p.sharedWithUids.contains(myUid)),
  );

  final entries = <_OrderEntry>[];
  for (final profile in visible) {
    try {
      final records = await MedicalRecordService.instance.fetchRecords(profile.id, limit: 100);
      for (final r in records) {
        if (_orderCategories.contains(r.category)) {
          entries.add(_OrderEntry(record: r, profileId: profile.id, profileName: profile.name));
        }
      }
    } on FirebaseException catch (e) {
      // Defensivo: si por algún motivo (datos locales desactualizados,
      // etc.) igual llega un permission-denied para un perfil puntual,
      // lo saltamos en vez de tirar abajo el resto de las órdenes.
      debugPrint('Órdenes: no se pudo leer el historial de ${profile.id}. $e');
    }
  }
  entries.sort((a, b) => b.record.date.compareTo(a.record.date));
  return entries;
}

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class OrdenScreen extends StatefulWidget {
  final VoidCallback? onBackToDashboard;

  /// Si viene, la pantalla muestra y crea órdenes solo de ese perfil (se usa
  /// al entrar desde el Diario). Sin él, es la pestaña general de la familia.
  final FamilyProfile? profile;

  const OrdenScreen({super.key, this.onBackToDashboard, this.profile});

  @override
  State<OrdenScreen> createState() => _OrdenScreenState();
}

class _OrdenScreenState extends State<OrdenScreen> {
  int _selectedFilter = 0; // 0=Todos, 1=Laboratorio, 2=Estudios, 3=Pendientes
  final _searchCtrl = TextEditingController();
  String _query = '';

  static const _filters = ['Todos', 'Laboratorio', 'Estudios', 'Pendientes'];

  Future<List<_OrderEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  void _load() {
    setState(() {
      _future = _fetchOrders(only: widget.profile);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_OrderEntry> _applyFilters(List<_OrderEntry> orders) {
    var result = orders;
    if (_selectedFilter == 1) {
      result = result.where((o) => o.record.category == RecordCategory.laboratorio).toList();
    } else if (_selectedFilter == 2) {
      result = result
          .where((o) => o.record.category == RecordCategory.estudio || o.record.category == RecordCategory.cardiologia)
          .toList();
    } else if (_selectedFilter == 3) {
      result = result.where((o) => o.record.status == RecordStatus.pendiente).toList();
    }
    if (_query.isNotEmpty) {
      result = result.where((o) {
        final r = o.record;
        return r.title.toLowerCase().contains(_query) ||
            r.professional.toLowerCase().contains(_query) ||
            r.institution.toLowerCase().contains(_query) ||
            o.profileName.toLowerCase().contains(_query);
      }).toList();
    }
    return result;
  }

  Future<void> _openNewOrder() async {
    final profiles = await ProfileService.instance.watchProfiles().first;
    if (!mounted) return;
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero agregá un perfil familiar para poder cargar una orden.')),
      );
      return;
    }
    FamilyProfile? target = widget.profile ?? (profiles.length == 1 ? profiles.first : null);
    if (target == null) {
      target = await showModalBottomSheet<FamilyProfile>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¿Para quién es la orden?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                ...profiles.map(
                      (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: p.type == ProfileType.mascota ? SaluteColors.terracotta : SaluteColors.darkGreen,
                      child: Icon(
                        p.type == ProfileType.mascota ? Icons.pets_outlined : Icons.person_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(p.relation.isNotEmpty ? p.relation : 'Familiar'),
                    onTap: () => Navigator.of(sheetContext).pop(p),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (target == null || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OrderFormScreen(profileId: target!.id, profileName: target.name)),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleStatus(_OrderEntry entry) async {
    final newStatus =
    entry.record.status == RecordStatus.pendiente ? RecordStatus.completado : RecordStatus.pendiente;
    try {
      await MedicalRecordService.instance.setStatus(entry.profileId, entry.record.id, newStatus);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el estado: $e')),
      );
    }
  }

  /// Abre el adjunto de la orden con el visor del sistema.
  Future<void> _openAttachment(_OrderEntry entry) async {
    final att = OrderAttachment.fromDetails(entry.record.details);
    final messenger = ScaffoldMessenger.of(context);
    if (att == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Esta orden no tiene archivo adjunto.')));
      return;
    }
    final ok = await AttachmentService.instance.open(att);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo abrir el archivo. Puede haberse cargado desde otro dispositivo.'),
      ));
    }
  }

  Future<void> _shareAttachment(_OrderEntry entry) async {
    final att = OrderAttachment.fromDetails(entry.record.details);
    final messenger = ScaffoldMessenger.of(context);
    if (att == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Esta orden no tiene archivo adjunto.')));
      return;
    }
    final ok = await AttachmentService.instance.share(att, text: entry.record.title);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
        content: Text('El archivo no está disponible en este dispositivo.'),
      ));
    }
  }

  void _showDetails(_OrderEntry entry) {
    final r = entry.record;
    final attachment = OrderAttachment.fromDetails(r.details);
    final ocrText = (r.details['ocrText'] as String?) ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(_categoryLabels[r.category] ?? 'Otro', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                const SizedBox(height: 16),
                _DetailRow(icon: Icons.person_outline, label: 'Perfil', value: entry.profileName),
                if (r.professional.isNotEmpty)
                  _DetailRow(icon: Icons.medical_services_outlined, label: 'Médico', value: r.professional),
                if (r.institution.isNotEmpty)
                  _DetailRow(icon: Icons.location_on_outlined, label: 'Institución', value: r.institution),
                _DetailRow(icon: Icons.event_outlined, label: 'Fecha', value: _fmtDate(r.date)),
                _DetailRow(
                  icon: Icons.flag_outlined,
                  label: 'Estado',
                  value: r.status == RecordStatus.pendiente ? 'Pendiente' : 'Completado',
                ),
                const SizedBox(height: 16),
                if (attachment == null)
                  const Text(
                    'Sin archivo adjunto.',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  )
                else ...[
                  _DetailRow(
                    icon: attachment.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                    label: 'Adjunto',
                    value: attachment.name,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openAttachment(entry),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Abrir'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _shareAttachment(entry),
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: const Text('Compartir'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (ocrText.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Texto reconocido', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(ocrText, style: const TextStyle(fontSize: 12)),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewOrder,
        backgroundColor: SaluteColors.primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: widget.profile != null ? 'Órdenes · ${widget.profile!.name}' : 'Mis Órdenes',
              onBack: widget.onBackToDashboard,
            ),
            Expanded(
              child: FutureBuilder<List<_OrderEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: SaluteColors.primaryGreen));
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(message: '${snapshot.error}', onRetry: _load);
                  }
                  final all = snapshot.data ?? [];
                  final filtered = _applyFilters(all);
                  final pendingCount = all.where((o) => o.record.status == RecordStatus.pendiente).length;

                  return RefreshIndicator(
                    color: SaluteColors.primaryGreen,
                    onRefresh: () async => _load(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      children: [
                        _StatsRow(total: all.length, pending: pendingCount),
                        const SizedBox(height: 20),
                        _SearchBar(controller: _searchCtrl),
                        const SizedBox(height: 16),
                        _FilterChips(
                          filters: _filters,
                          selectedIndex: _selectedFilter,
                          onSelected: (i) => setState(() => _selectedFilter = i),
                        ),
                        const SizedBox(height: 20),
                        if (filtered.isEmpty)
                          _EmptyState(hasAny: all.isNotEmpty)
                        else
                          ...filtered.map(
                                (entry) => _OrderCard(
                              entry: entry,
                              onTap: () => _showDetails(entry),
                              onToggleStatus: () => _toggleStatus(entry),
                              onAttachment: () => _openAttachment(entry),
                            ),
                          ),
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
        children: [
          Icon(icon, size: 18, color: SaluteColors.primaryGreen),
          const SizedBox(width: 10),
          Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: SaluteColors.terracotta, size: 36),
            const SizedBox(height: 12),
            Text('No se pudieron cargar las órdenes.\n$message', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasAny;
  const _EmptyState({required this.hasAny});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.folder_open_outlined, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            hasAny ? 'Ninguna orden coincide con el filtro.' : 'Todavía no cargaste ninguna orden médica.',
            style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUSCADOR
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14, color: Colors.black87),
        decoration: InputDecoration(
          hintText: 'Buscar estudio, médico o institución...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: SaluteColors.primaryGreen,
              width: 1.5,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int total, pending;
  const _StatsRow({required this.total, required this.pending});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildBox('TOTAL DE ÓRDENES', total.toString(), Colors.white, SaluteColors.primaryGreen),
        const SizedBox(width: 16),
        _buildBox('PENDIENTES', pending.toString(), SaluteColors.primaryGreen, Colors.white),
      ],
    );
  }

  Widget _buildBox(String title, String val, Color bg, Color txt) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: bg == Colors.white ? Colors.grey.shade200 : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: txt.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            val,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: txt,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTROS
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final List<String> filters;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _FilterChips({
    required this.filters,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(filters.length, (i) {
          final selected = i == selectedIndex;
          return Padding(
            padding: EdgeInsets.only(right: i < filters.length - 1 ? 10 : 0),
            child: GestureDetector(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected ? SaluteColors.primaryGreen : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: !selected
                      ? Border.all(color: Colors.grey[300]!, width: 1)
                      : null,
                ),
                child: Text(
                  filters[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD DE ORDEN
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final _OrderEntry entry;
  final VoidCallback onTap;
  final VoidCallback onToggleStatus;
  final VoidCallback onAttachment;
  const _OrderCard({
    required this.entry,
    required this.onTap,
    required this.onToggleStatus,
    required this.onAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final order = entry.record;
    final bool isPending = order.status == RecordStatus.pendiente;
    final bool hasAttachment = OrderAttachment.fromDetails(order.details) != null;
    final Color accent = _categoryColors[order.category] ?? SaluteColors.primaryGreen;
    final IconData icon = _categoryIcons[order.category] ?? Icons.description_outlined;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fila superior: Icono + Título + Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accent.withValues(alpha: 0.15), accent.withValues(alpha: 0.08)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: accent.withValues(alpha: 0.2), width: 1.5),
                        ),
                        child: Icon(icon, color: accent, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Colors.black87,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                entry.profileName,
                                if (order.professional.isNotEmpty) order.professional,
                                _fmtDate(order.date),
                              ].join(' • '),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Badge de estado, tocable: alterna pendiente ⇄ completado
                      GestureDetector(
                        onTap: onToggleStatus,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: (isPending ? SaluteColors.lightBrown : SaluteColors.lightGreen)
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (isPending ? SaluteColors.brownOrange : SaluteColors.primaryGreen)
                                  .withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            isPending ? 'PENDIENTE' : 'COMPLETO',
                            style: TextStyle(
                              color: isPending ? SaluteColors.brownOrange : SaluteColors.darkGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (order.institution.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            order.institution,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Divider(color: SaluteColors.bgColor, thickness: 1, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _categoryLabels[order.category] ?? 'Otro',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Row(
                        children: [
                          _ActionButton(icon: Icons.remove_red_eye_outlined, tooltip: 'Ver detalles', onTap: onTap),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: hasAttachment ? Icons.attach_file_rounded : Icons.attach_file_outlined,
                            tooltip: hasAttachment ? 'Abrir adjunto' : 'Sin adjunto',
                            onTap: onAttachment,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Botón pequeño circular para el footer
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: SaluteColors.bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Icon(
            icon,
            color: SaluteColors.primaryGreen,
            size: 20,
          ),
        ),
      ),
    );
  }
}