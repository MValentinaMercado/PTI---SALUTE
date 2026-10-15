import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/medicine_item.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/medication_botiquin_link.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/core/services/medicine_item_service.dart';

// --- Pantalla Principal ---
class BotiquinScreen extends StatefulWidget {
  final VoidCallback? onBackToDashboard;
  const BotiquinScreen({super.key, this.onBackToDashboard});

  @override
  State<BotiquinScreen> createState() => _BotiquinScreenState();
}

class _BotiquinScreenState extends State<BotiquinScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'Todos';

  /// Tratamientos activos de los perfiles que administro (para cruzarlos
  /// con el inventario: "en uso por", días de stock y medicación que
  /// todavía no está en el botiquín).
  List<ProfileMedication> _treatments = const [];

  @override
  void initState() {
    super.initState();
    _loadTreatments();
  }

  Future<void> _loadTreatments() async {
    try {
      final list = await MedicationService.instance.loadAllManagedByMe();
      if (mounted) setState(() => _treatments = list);
    } catch (_) {
      // El botiquín funciona igual sin este cruce.
    }
  }

  /// "En uso: Juana, Tomás · alcanza para ~6 días", o null si ningún
  /// tratamiento activo usa este ítem.
  String? _usageLabel(MedicineItem item, List<MedicineItem> all) {
    final users = _treatments
        .where(
          (t) =>
              MedicationBotiquinLink.resolveItem(t.medication, all)?.id ==
              item.id,
        )
        .toList();
    if (users.isEmpty) return null;
    final names = users.map((t) => t.profile.name).toSet().join(', ');
    final perDay = users.fold<int>(
      0,
      (sum, t) => sum + t.medication.unitsPerDay,
    );
    if (perDay <= 0) return 'En uso: $names';
    final days = item.currentStock ~/ perDay;
    return 'En uso: $names · alcanza para ~$days día${days == 1 ? '' : 's'}';
  }

  MedicineItem _prefillFor(Medication m) {
    return MedicineItem(
      id: '',
      name: m.name,
      dosage: m.dose,
      schedule: m.timesOfDay.isEmpty
          ? 'Sin frecuencia definida'
          : '${m.timesOfDay.length} ${m.timesOfDay.length == 1 ? 'toma' : 'tomas'} por día',
      expirationDate: DateTime.now().add(const Duration(days: 365)),
      currentStock: 0,
      totalStock: 0,
    );
  }

  List<MedicineItem> _applyFilters(List<MedicineItem> medicines) {
    final query = _searchController.text.toLowerCase();
    return medicines.where((m) {
      final matchesSearch =
          m.name.toLowerCase().contains(query) ||
          m.dosage.toLowerCase().contains(query);
      if (!matchesSearch) return false;

      switch (_selectedFilter) {
        case 'Stock Bajo':
          return m.isCritical;
        case 'Vencidos':
          return m.isExpired;
        case 'Activos':
          return !m.isCritical && !m.isExpired;
        default:
          return true;
      }
    }).toList();
  }

  /// [prefill] precarga el formulario (alta desde un tratamiento); [linkTo]
  /// vincula ese tratamiento al ítem recién creado.
  void _showMedicineForm({
    MedicineItem? medicine,
    MedicineItem? prefill,
    ProfileMedication? linkTo,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MedicineForm(
        medicine: medicine,
        prefill: prefill,
        onSave: (item) async {
          try {
            if (medicine == null) {
              final newId = await MedicineItemService.instance.addItem(item);
              if (linkTo != null) {
                await MedicationService.instance.linkBotiquin(
                  linkTo.profile.id,
                  linkTo.medication.id,
                  newId,
                );
              }
            } else {
              await MedicineItemService.instance.updateItem(item);
            }
            if (mounted) _loadTreatments();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
          }
        },
      ),
    );
  }

  Future<void> _updateStock(MedicineItem medicine, int delta) async {
    final newStock = (medicine.currentStock + delta).clamp(
      0,
      medicine.totalStock,
    );
    try {
      await MedicineItemService.instance.updateStock(medicine.id, newStock);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el stock: $e')),
      );
    }
  }

  Future<void> _discard(MedicineItem medicine) async {
    try {
      await MedicineItemService.instance.deleteItem(medicine.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo descartar: $e')));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showMedicineForm(),
        backgroundColor: SaluteColors.primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Mi Botiquín',
              onBack: widget.onBackToDashboard,
            ),
            Expanded(
              child: StreamBuilder<List<MedicineItem>>(
                stream: MedicineItemService.instance.watchAll(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudo cargar el botiquín: ${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: SaluteColors.primaryGreen,
                      ),
                    );
                  }

                  final medicines = snapshot.data!;
                  final filtered = _applyFilters(medicines);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DsSectionTitle(title: 'Inventario'),
                        const SizedBox(height: 16),
                        _StatsCards(medicines: medicines),
                        const SizedBox(height: 20),
                        _UntrackedTreatments(
                          treatments: _treatments
                              .where(
                                (t) =>
                                    MedicationBotiquinLink.resolveItem(
                                      t.medication,
                                      medicines,
                                    ) ==
                                    null,
                              )
                              .toList(),
                          onAdd: (t) => _showMedicineForm(
                            prefill: _prefillFor(t.medication),
                            linkTo: t,
                          ),
                        ),
                        TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Buscar medicamento...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _FilterChips(
                          selected: _selectedFilter,
                          onChanged: (f) => setState(() => _selectedFilter = f),
                        ),
                        const SizedBox(height: 20),
                        if (medicines.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                'Todavía no cargaste ningún medicamento.\nTocá el "+" para agregar el primero.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ),
                          )
                        else if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                'Ningún medicamento coincide con el filtro.',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ),
                          )
                        else
                          ...filtered.map(
                            (m) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _MedicineCard(
                                medicine: m,
                                usage: _usageLabel(m, medicines),
                                onIncrement: () => _updateStock(m, 1),
                                onDecrement: () => _updateStock(m, -1),
                                onEdit: () => _showMedicineForm(medicine: m),
                                onDiscard: () => _discard(m),
                              ),
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

// --- Componentes ---

class _FilterChips extends StatelessWidget {
  final String selected;
  final Function(String) onChanged;
  const _FilterChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['Todos', 'Activos', 'Stock Bajo', 'Vencidos']
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(
                    f,
                    style: TextStyle(
                      color: selected == f ? Colors.white : Colors.black87,
                    ),
                  ),
                  selected: selected == f,
                  selectedColor: SaluteColors.primaryGreen,
                  backgroundColor: Colors.grey.shade100,
                  onSelected: (_) => onChanged(f),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final MedicineItem medicine;
  final String? usage;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onEdit;
  final VoidCallback onDiscard;

  const _MedicineCard({
    required this.medicine,
    this.usage,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEdit,
    required this.onDiscard,
  });

  Color get _statusColor => medicine.isExpired
      ? const Color(0xFFC62828)
      : medicine.isCritical
      ? const Color(0xFFE67E22)
      : Colors.grey.shade400;
  Color get _bgColor => medicine.isExpired
      ? const Color(0xFFFFF5F5)
      : medicine.isCritical
      ? const Color(0xFFFFFBF0)
      : Colors.white;

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicine.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${medicine.dosage} • ${medicine.schedule}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      medicine.isExpired
                          ? 'Venció el ${_fmtDate(medicine.expirationDate)}'
                          : 'Vence ${_fmtDate(medicine.expirationDate)}',
                      style: TextStyle(
                        color: medicine.isExpired
                            ? const Color(0xFFC62828)
                            : Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                    if (usage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          usage!,
                          style: const TextStyle(
                            color: SaluteColors.primaryGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                onSelected: (value) => value == 'edit' ? onEdit() : onDiscard(),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Descartar',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: medicine.stockPercentage,
            valueColor: AlwaysStoppedAnimation(_statusColor),
            backgroundColor: Colors.grey.shade100,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${medicine.currentStock} / ${medicine.totalStock} unidades',
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: medicine.currentStock > 0 ? onDecrement : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  IconButton(
                    onPressed: medicine.currentStock < medicine.totalStock
                        ? onIncrement
                        : null,
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MedicineForm extends StatefulWidget {
  final MedicineItem? medicine;

  /// Solo precarga los campos (no es una edición: `medicine` sigue null y
  /// se guarda como ítem nuevo). Lo usa el alta desde un tratamiento.
  final MedicineItem? prefill;
  final void Function(MedicineItem) onSave;
  const MedicineForm({
    super.key,
    this.medicine,
    this.prefill,
    required this.onSave,
  });

  @override
  State<MedicineForm> createState() => _MedicineFormState();
}

class _MedicineFormState extends State<MedicineForm> {
  late TextEditingController _name, _dose, _schedule, _stock;
  late DateTime _expirationDate;

  @override
  void initState() {
    super.initState();
    final src = widget.medicine ?? widget.prefill;
    _name = TextEditingController(text: src?.name ?? '');
    _dose = TextEditingController(text: src?.dosage ?? '');
    _schedule = TextEditingController(text: src?.schedule ?? '');
    _stock = TextEditingController(text: (src?.totalStock ?? 0).toString());
    _expirationDate =
        src?.expirationDate ?? DateTime.now().add(const Duration(days: 365));
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _schedule.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _pickExpirationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _expirationDate = picked);
  }

  void _submit() {
    final totalStock = int.tryParse(_stock.text) ?? 0;
    if (_name.text.trim().isEmpty) return;
    widget.onSave(
      MedicineItem(
        id: widget.medicine?.id ?? '',
        name: _name.text.trim(),
        dosage: _dose.text.trim(),
        schedule: _schedule.text.trim().isEmpty
            ? 'Sin frecuencia definida'
            : _schedule.text.trim(),
        expirationDate: _expirationDate,
        // Al crear, el stock actual arranca igual al total. Al editar, se
        // conserva el stock actual salvo que el usuario haya subido el total
        // (ej. compró una caja nueva), en cuyo caso no lo tocamos acá — el
        // ajuste fino de unidades restantes se hace con los botones +/-.
        currentStock: widget.medicine == null
            ? totalStock
            : widget.medicine!.currentStock.clamp(0, totalStock),
        totalStock: totalStock,
      ),
    );
    Navigator.pop(context);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.medicine == null
                ? 'Agregar Medicamento'
                : 'Editar Medicamento',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _dose,
            decoration: const InputDecoration(labelText: 'Dosis (ej: 500mg)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _schedule,
            decoration: const InputDecoration(
              labelText: 'Frecuencia (ej: 1 c/8h)',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _stock,
            decoration: const InputDecoration(
              labelText: 'Stock Total (unidades)',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickExpirationDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de vencimiento',
              ),
              child: Text(_fmtDate(_expirationDate)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: SaluteColors.primaryGreen,
              ),
              child: const Text(
                'Guardar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Tratamientos activos que todavía no tienen un ítem en el botiquín
/// (ni vinculado ni con el mismo nombre). Es el "medicamento detectado":
/// se ofrece cargarlo con los datos ya conocidos (nombre, dosis) y, al
/// guardarlo, queda vinculado al tratamiento.
class _UntrackedTreatments extends StatelessWidget {
  final List<ProfileMedication> treatments;
  final void Function(ProfileMedication) onAdd;
  const _UntrackedTreatments({required this.treatments, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    if (treatments.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SaluteColors.lightGreen.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            treatments.length == 1
                ? '1 tratamiento activo no está en tu botiquín'
                : '${treatments.length} tratamientos activos no están en tu botiquín',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: SaluteColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Agregalos para llevar el stock y recibir aviso cuando no alcance.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          ...treatments.map(
            (t) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.medication_outlined,
                    size: 18,
                    color: SaluteColors.primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${t.medication.name} · ${t.profile.name}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => onAdd(t),
                    child: const Text('Agregar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCards extends StatelessWidget {
  final List<MedicineItem> medicines;
  const _StatsCards({required this.medicines});

  @override
  Widget build(BuildContext context) {
    final int total = medicines.length;
    final int alertas = medicines
        .where((m) => m.isCritical || m.isExpired)
        .length;
    final int reposicion = medicines.where((m) => m.currentStock < 5).length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.medication_outlined,
                title: 'TOTAL',
                value: '$total',
                subtitle: 'Productos activos',
                color: SaluteColors.primaryGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.warning_amber_rounded,
                title: 'ALERTAS',
                value: '$alertas',
                subtitle: 'Por caducar pronto',
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.inventory_2_outlined,
          title: 'REPOSICIÓN',
          value: '$reposicion',
          subtitle: 'Stock bajo',
          color: Colors.orange,
        ),
      ],
    );
  }
}
