import 'package:saluteapp/components/text_scale.dart';
import 'package:saluteapp/components/a11y_tap.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/active_profile_controller.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/services/agenda_service.dart';
import 'package:saluteapp/profile/agenda_event_form_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELO (solo UI: el selector de días es un rango de fechas, no un evento)
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarDay {
  final DateTime date;
  const _CalendarDay(this.date);

  bool isSameDayAs(DateTime other) =>
      date.year == other.year && date.month == other.month && date.day == other.day;
}

const _weekdayLabels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _weekdayLabelsShort = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const _monthLabels = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];
const _monthLabelsFull = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto',
  'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

const _typeIcons = {
  AgendaEventType.turno: Icons.event_available,
  AgendaEventType.estudio: Icons.biotech_outlined,
  AgendaEventType.vacuna: Icons.vaccines_outlined,
  AgendaEventType.control: Icons.monitor_heart_outlined,
  AgendaEventType.medicacion: Icons.medication_outlined,
  AgendaEventType.otro: Icons.event_note_outlined,
};

const _statusLabels = {
  AgendaEventStatus.pendiente: 'Pendiente',
  AgendaEventStatus.completado: 'Completado',
  AgendaEventStatus.cancelado: 'Cancelado',
};

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

/// Flujo:
///   Agenda
///    ├── Todas → todos los eventos (agrupados por día)
///    ├── Mes   → grilla del mes; tocar un día filtra la lista de abajo
///    └── Semana → tira de 7 días navegable; tocar un día filtra la lista
enum _MainView { todas, mes, dia }

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  _MainView _view = _MainView.dia;
  int _statusFilter = 0; // 0=Todos, 1=Pendientes, 2=Completados

  // Selección múltiple (solo en la vista "Todas").
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  late DateTime _selectedDay; // usado por Día y Mes
  late DateTime _dayWindowStart; // arranque de la tira de 7 días de Día
  late DateTime _visibleMonth; // mes que se muestra en Mes (día 1 de ese mes)

  static const _statusLabelsFilter = ['Todos', 'Pendientes', 'Completados'];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    _selectedDay = base;
    _dayWindowStart = base.subtract(const Duration(days: 1));
    _visibleMonth = DateTime(today.year, today.month, 1);
  }

  List<_CalendarDay> get _dayWindow =>
      List.generate(7, (i) => _CalendarDay(_dayWindowStart.add(Duration(days: i))));

  void _selectDay(DateTime d) {
    setState(() {
      _selectedDay = d;
      _visibleMonth = DateTime(d.year, d.month, 1);
      // Si el día elegido (ej: desde el calendario del mes) quedó fuera
      // de la tira de 7 días de la vista Día, recentramos la tira.
      if (d.isBefore(_dayWindowStart) || d.isAfter(_dayWindowStart.add(const Duration(days: 6)))) {
        _dayWindowStart = d.subtract(const Duration(days: 1));
      }
    });
  }

  void _shiftDayWindow(int days) {
    setState(() => _dayWindowStart = _dayWindowStart.add(Duration(days: days)));
  }

  void _shiftMonth(int months) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + months, 1));
  }

  Future<void> _pickAnyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) _selectDay(DateTime(picked.year, picked.month, picked.day));
  }

  List<AgendaEvent> _applyStatusFilter(List<AgendaEvent> events) {
    switch (_statusFilter) {
      case 1:
        return events.where((e) => e.isUpcoming).toList();
      case 2:
        return events.where((e) => e.status == AgendaEventStatus.completado).toList();
      default:
        return events;
    }
  }

  /// BUG-006 (Parte 3): en vez de preguntar "¿para quién es el turno?"
  /// cada vez, usamos directamente el perfil activo global
  /// (`ActiveProfileController`, ver selector en el Home). Si el usuario
  /// quiere cargar un turno para otro perfil (ej: un hijo), primero
  /// cambia el perfil activo desde ahí.
  Future<void> _openNewEventForActiveProfile() async {
    final active = ActiveProfileController.instance.active;
    if (active == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esperá a que cargue tu perfil para poder cargar turnos.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgendaEventFormScreen(profileId: active.id, profileName: active.name),
      ),
    );
  }

  // ── Selección múltiple ──

  void _startSelecting([AgendaEvent? first]) {
    setState(() {
      _selecting = true;
      _selectedIds
        ..clear()
        ..addAll(first == null ? const [] : [first.id]);
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(AgendaEvent e) {
    setState(() {
      if (!_selectedIds.add(e.id)) _selectedIds.remove(e.id);
    });
  }

  void _toggleSelectAll(List<AgendaEvent> visible) {
    setState(() {
      final allSelected = visible.isNotEmpty && visible.every((e) => _selectedIds.contains(e.id));
      if (allSelected) {
        _selectedIds.removeAll(visible.map((e) => e.id));
      } else {
        _selectedIds.addAll(visible.map((e) => e.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await _confirmDelete(
      title: ids.length == 1 ? '¿Eliminar 1 evento?' : '¿Eliminar ${ids.length} eventos?',
      message: 'Esta acción no se puede deshacer.',
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await AgendaService.instance.deleteEvents(ids);
    if (!mounted) return;
    _exitSelecting();
    messenger.showSnackBar(SnackBar(
      content: Text(deleted == ids.length
          ? (deleted == 1 ? 'Evento eliminado.' : '$deleted eventos eliminados.')
          : 'Se eliminaron $deleted de ${ids.length} eventos. Probá de nuevo con el resto.'),
    ));
  }

  Future<bool?> _confirmDelete({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB03A3A)),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // ── Ver / editar / eliminar un evento ──

  Future<void> _openDetails(AgendaEvent event) async {
    final action = await showModalBottomSheet<_EventAction>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EventDetailSheet(event: event),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _EventAction.edit:
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => AgendaEventFormScreen(
              profileId: event.profileId,
              profileName: event.profileName,
              existing: event,
            ),
          ),
        );
        if (saved == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Evento actualizado.')));
        }
      case _EventAction.delete:
        final ok = await _confirmDelete(
          title: '¿Eliminar este evento?',
          message: '"${event.title}" se va a borrar de la agenda. Esta acción no se puede deshacer.',
        );
        if (ok != true || !mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        try {
          await AgendaService.instance.deleteEvent(event.id);
          messenger.showSnackBar(const SnackBar(content: Text('Evento eliminado.')));
        } catch (_) {
          messenger.showSnackBar(const SnackBar(content: Text('No se pudo eliminar. Intentá de nuevo.')));
        }
      case _EventAction.toggleStatus:
        _toggleStatus(event);
    }
  }

  void _toggleStatus(AgendaEvent event) {
    final next = event.status == AgendaEventStatus.completado
        ? AgendaEventStatus.pendiente
        : AgendaEventStatus.completado;
    AgendaService.instance.setStatus(event.id, next);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Con selección activa, "atrás" sale de la selección en vez de cerrar la agenda.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelecting();
      },
      child: Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AgendaAppBar(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _MainTabBar(
                selected: _view,
                onSelected: (v) => setState(() {
                  _view = v;
                  _selecting = false;
                  _selectedIds.clear();
                }),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<AgendaEvent>>(
                stream: AgendaService.instance.watchAll(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudo cargar la agenda.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: SaluteColors.textMuted),
                        ),
                      ),
                    );
                  }
                  final allEvents = snapshot.data ?? const [];
                  switch (_view) {
                    case _MainView.todas:
                      return _TodasView(
                        events: _applyStatusFilter(allEvents),
                        statusFilter: _statusFilter,
                        statusLabels: _statusLabelsFilter,
                        onStatusFilterChanged: (i) => setState(() => _statusFilter = i),
                        onToggleStatus: _toggleStatus,
                        onAdd: _openNewEventForActiveProfile,
                        onOpen: _openDetails,
                        selecting: _selecting,
                        selectedIds: _selectedIds,
                        onStartSelecting: _startSelecting,
                        onExitSelecting: _exitSelecting,
                        onToggleSelected: _toggleSelected,
                        onToggleSelectAll: () => _toggleSelectAll(_applyStatusFilter(allEvents)),
                        onDeleteSelected: _deleteSelected,
                      );
                    case _MainView.mes:
                      return _MesView(
                        allEvents: allEvents,
                        visibleMonth: _visibleMonth,
                        selectedDay: _selectedDay,
                        onPrevMonth: () => _shiftMonth(-1),
                        onNextMonth: () => _shiftMonth(1),
                        onDaySelected: _selectDay,
                        dayEvents: _applyStatusFilter(
                          allEvents.where((e) => _sameDay(e.date, _selectedDay)).toList(),
                        ),
                        onToggleStatus: _toggleStatus,
                        onAdd: _openNewEventForActiveProfile,
                        onOpen: _openDetails,
                      );
                    case _MainView.dia:
                    // Sin filtro de estado en esta vista: se muestran
                    // todos los eventos del día seleccionado.
                      final dayEvents = allEvents
                          .where((e) => _sameDay(e.date, _selectedDay))
                          .toList()
                        ..sort((a, b) => a.date.compareTo(b.date));
                      return _DiaView(
                        days: _dayWindow,
                        selectedDay: _selectedDay,
                        onDaySelected: _selectDay,
                        onPrevWeek: () => _shiftDayWindow(-7),
                        onNextWeek: () => _shiftDayWindow(7),
                        onPickDate: _pickAnyDate,
                        events: dayEvents,
                        onToggleStatus: _toggleStatus,
                        onAdd: _openNewEventForActiveProfile,
                        onOpen: _openDetails,
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              tooltip: 'Nuevo evento',
              backgroundColor: SaluteColors.primaryGreen,
              onPressed: _openNewEventForActiveProfile,
              child: const Icon(Icons.add, color: Colors.white),
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _AgendaAppBar extends StatelessWidget {
  const _AgendaAppBar();

  @override
  Widget build(BuildContext context) {
    return const AppHeader.secondary(title: 'Agenda');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABS PRINCIPALES: Todas / Mes / Semana
// ─────────────────────────────────────────────────────────────────────────────

class _MainTabBar extends StatelessWidget {
  final _MainView selected;
  final ValueChanged<_MainView> onSelected;
  const _MainTabBar({required this.selected, required this.onSelected});

  static const _entries = [
    (_MainView.todas, 'Todas'),
    (_MainView.mes, 'Mes'),
    (_MainView.dia, 'Semana'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: _entries.map((e) {
          final isSelected = selected == e.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(e.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? SaluteColors.primaryGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  e.$2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : SaluteColors.textMuted,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VISTA "TODAS": lista plana de todos los eventos, agrupados por día
// ─────────────────────────────────────────────────────────────────────────────

class _TodasView extends StatelessWidget {
  final List<AgendaEvent> events;
  final int statusFilter;
  final List<String> statusLabels;
  final ValueChanged<int> onStatusFilterChanged;
  final ValueChanged<AgendaEvent> onToggleStatus;
  final VoidCallback onAdd;
  final ValueChanged<AgendaEvent> onOpen;

  // Selección múltiple
  final bool selecting;
  final Set<String> selectedIds;
  final ValueChanged<AgendaEvent?> onStartSelecting;
  final VoidCallback onExitSelecting;
  final ValueChanged<AgendaEvent> onToggleSelected;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onDeleteSelected;

  const _TodasView({
    required this.events,
    required this.statusFilter,
    required this.statusLabels,
    required this.onStatusFilterChanged,
    required this.onToggleStatus,
    required this.onAdd,
    required this.onOpen,
    required this.selecting,
    required this.selectedIds,
    required this.onStartSelecting,
    required this.onExitSelecting,
    required this.onToggleSelected,
    required this.onToggleSelectAll,
    required this.onDeleteSelected,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...events]..sort((a, b) => a.date.compareTo(b.date));

    // Agrupamos por día para que una lista larga (semanas/meses de turnos)
    // se pueda escanear rápido, en vez de un timestamp suelto por fila.
    final groups = <DateTime, List<AgendaEvent>>{};
    for (final e in sorted) {
      final key = DateTime(e.date.year, e.date.month, e.date.day);
      groups.putIfAbsent(key, () => []).add(e);
    }
    final orderedDays = groups.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _FilterBar(
            labels: statusLabels,
            selectedIndex: statusFilter,
            onFilterSelected: onStatusFilterChanged,
          ),
        ),
        const SizedBox(height: 6),
        if (selecting)
          _SelectionBar(
            count: selectedIds.length,
            allSelected: sorted.isNotEmpty && sorted.every((e) => selectedIds.contains(e.id)),
            onClose: onExitSelecting,
            onToggleAll: onToggleSelectAll,
            onDelete: onDeleteSelected,
          )
        else if (sorted.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onStartSelecting(null),
                icon: const Icon(Icons.checklist_rounded, size: 18, color: SaluteColors.primaryGreen),
                label: const Text(
                  'Seleccionar',
                  style: TextStyle(color: SaluteColors.primaryGreen, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: orderedDays.isEmpty
              ? _EmptyState(
            message: 'No hay eventos agendados todavía.',
            onAdd: onAdd,
          )
              : ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: orderedDays.length,
            itemBuilder: (_, i) {
              final day = orderedDays[i];
              final dayEvents = groups[day]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                    child: _DayHeader(date: day),
                  ),
                  ...dayEvents.map((e) => _EventRow(
                    event: e,
                    onToggleStatus: () => onToggleStatus(e),
                    onOpen: () => selecting ? onToggleSelected(e) : onOpen(e),
                    onLongPress: selecting ? null : () => onStartSelecting(e),
                    selecting: selecting,
                    selected: selectedIds.contains(e.id),
                  )),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime date;
  const _DayHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = _sameDay(date, today);
    final label = isToday
        ? 'Hoy · ${date.day} de ${_monthLabelsFull[date.month - 1]}'
        : '${_weekdayLabels[date.weekday - 1]} ${date.day} de ${_monthLabelsFull[date.month - 1]}';
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isToday ? SaluteColors.primaryGreen : SaluteColors.textMuted,
        letterSpacing: 0.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VISTA "MES": grilla del mes + lista del día seleccionado
// ─────────────────────────────────────────────────────────────────────────────

class _MesView extends StatelessWidget {
  final List<AgendaEvent> allEvents;
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDaySelected;
  final List<AgendaEvent> dayEvents;
  final ValueChanged<AgendaEvent> onToggleStatus;
  final VoidCallback onAdd;
  final ValueChanged<AgendaEvent> onOpen;

  const _MesView({
    required this.allEvents,
    required this.visibleMonth,
    required this.selectedDay,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onDaySelected,
    required this.dayEvents,
    required this.onToggleStatus,
    required this.onAdd,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    // Días con al menos un evento este mes, para el puntito debajo del número.
    final daysWithEvents = allEvents
        .where((e) => e.date.year == visibleMonth.year && e.date.month == visibleMonth.month)
        .map((e) => e.date.day)
        .toSet();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Mes anterior',
                      onPressed: onPrevMonth,
                      icon: const Icon(Icons.chevron_left, color: SaluteColors.primaryGreen),
                    ),
                    Expanded(
                      child: Text(
                        '${_monthLabelsFull[visibleMonth.month - 1]} ${visibleMonth.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mes siguiente',
                      onPressed: onNextMonth,
                      icon: const Icon(Icons.chevron_right, color: SaluteColors.primaryGreen),
                    ),
                  ],
                ),
                Row(
                  children: _weekdayLabelsShort
                      .map((l) => Expanded(
                    child: Center(
                      child: Text(l, style: TextStyle(fontSize: 12, color: SaluteColors.textMuted, fontWeight: FontWeight.w600)),
                    ),
                  ))
                      .toList(),
                ),
                const SizedBox(height: 4),
                _MonthGrid(
                  month: visibleMonth,
                  selectedDay: selectedDay,
                  daysWithEvents: daysWithEvents,
                  onDaySelected: onDaySelected,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _DayHeader(date: selectedDay),
        ),
        const SizedBox(height: 8),
        if (dayEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, color: SaluteColors.primaryGreen),
                label: const Text('Agregar turno para este día', style: TextStyle(color: SaluteColors.primaryGreen)),
              ),
            ),
          )
        else
          ...dayEvents.map((e) => _EventRow(event: e, onToggleStatus: () => onToggleStatus(e), onOpen: () => onOpen(e))),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month; // día 1 del mes visible
  final DateTime selectedDay;
  final Set<int> daysWithEvents;
  final ValueChanged<DateTime> onDaySelected;

  const _MonthGrid({
    required this.month,
    required this.selectedDay,
    required this.daysWithEvents,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // weekday: 1=lunes..7=domingo → columnas antes del día 1.
    final leadingBlanks = month.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
      itemCount: rows * 7,
      itemBuilder: (_, i) {
        final dayNum = i - leadingBlanks + 1;
        if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();
        final date = DateTime(month.year, month.month, dayNum);
        final isSelected = _sameDay(date, selectedDay);
        final isToday = _sameDay(date, today);
        final hasEvents = daysWithEvents.contains(dayNum);

        return Padding(
          padding: const EdgeInsets.all(3),
          child: GestureDetector(
            onTap: () => onDaySelected(date),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? SaluteColors.primaryGreen : Colors.transparent,
                shape: BoxShape.circle,
                border: !isSelected && isToday
                    ? Border.all(color: SaluteColors.primaryGreen, width: 1.4)
                    : null,
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$dayNum',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (hasEvents)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : SaluteColors.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VISTA "SEMANA": tira de 7 días navegable + lista del día seleccionado
// ─────────────────────────────────────────────────────────────────────────────

class _DiaView extends StatelessWidget {
  final List<_CalendarDay> days;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onPickDate;
  final List<AgendaEvent> events;
  final ValueChanged<AgendaEvent> onToggleStatus;
  final VoidCallback onAdd;
  final ValueChanged<AgendaEvent> onOpen;

  const _DiaView({
    required this.days,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onPickDate,
    required this.events,
    required this.onToggleStatus,
    required this.onAdd,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Semana anterior',
                onPressed: onPrevWeek,
                icon: Icon(Icons.chevron_left, color: SaluteColors.textMuted),
              ),
              Expanded(
                child: Center(
                  child: A11yTap(
                    onTap: onPickDate,
                    label: 'Elegir fecha',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.calendar_today_outlined, size: 16, color: SaluteColors.primaryGreen),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text('Elegir fecha', style: TextStyle(color: SaluteColors.primaryGreen, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Semana siguiente',
                onPressed: onNextWeek,
                icon: Icon(Icons.chevron_right, color: SaluteColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DaySelector(days: days, selectedDay: selectedDay, onDaySelected: onDaySelected),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: _TimelineHeader(),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: events.isEmpty
              ? _EmptyState(message: 'No hay eventos para este día.', onAdd: onAdd)
              : ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: events.length,
            itemBuilder: (_, i) => _EventRow(
              event: events[i],
              onToggleStatus: () => onToggleStatus(events[i]),
              onOpen: () => onOpen(events[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTOR DE DÍAS (tira horizontal)
// ─────────────────────────────────────────────────────────────────────────────

class _DaySelector extends StatelessWidget {
  final List<_CalendarDay> days;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  const _DaySelector({
    required this.days,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: scaledHeight(context, 100),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final day = days[i];
          final selected = day.isSameDayAs(selectedDay);
          return GestureDetector(
            onTap: () => onDaySelected(day.date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 72,
              decoration: BoxDecoration(
                color: selected ? SaluteColors.primaryGreen : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _monthLabels[day.date.month - 1],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: selected ? Colors.white70 : SaluteColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.date.day}',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _weekdayLabels[day.date.weekday - 1],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: selected ? Colors.white70 : SaluteColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTROS DE ESTADO (Todos / Pendientes / Completados)
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onFilterSelected;

  const _FilterBar({
    required this.labels,
    required this.selectedIndex,
    required this.onFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final selected = i == selectedIndex;
        return Padding(
          padding: EdgeInsets.only(right: i < labels.length - 1 ? 10 : 0),
          child: GestureDetector(
            onTap: () => onFilterSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? SaluteColors.primaryGreen : SaluteColors.lightGreen.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : SaluteColors.primaryGreen,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER DE COLUMNAS (Hora / Tareas)
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            'Hora',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SaluteColors.textMuted),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'Tareas',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SaluteColors.textMuted),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILA DE EVENTO
// ─────────────────────────────────────────────────────────────────────────────

class _EventRow extends StatelessWidget {
  final AgendaEvent event;
  final VoidCallback onToggleStatus;

  /// Tocar la fila abre el detalle (o, en modo selección, marca/desmarca).
  final VoidCallback onOpen;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  const _EventRow({
    required this.event,
    required this.onToggleStatus,
    required this.onOpen,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  String get _time =>
      '${event.date.hour.toString().padLeft(2, '0')}:${event.date.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final done = event.status == AgendaEventStatus.completado;
    return Semantics(
      button: true,
      selected: selecting ? selected : null,
      label: selecting
          ? '${event.title}, ${selected ? 'seleccionado' : 'no seleccionado'}'
          : 'Ver evento: ${event.title}',
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        child: Container(
          color: selected ? SaluteColors.lightGreen.withValues(alpha: 0.35) : Colors.transparent,
          child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Checkbox(
                value: selected,
                onChanged: (_) => onOpen(),
                activeColor: SaluteColors.primaryGreen,
                visualDensity: VisualDensity.compact,
              ),
            ),
          SizedBox(
            width: selecting ? 68 : 80,
            child: Padding(
              padding: EdgeInsets.fromLTRB(selecting ? 4 : 20, 20, 0, 20),
              child: Text(
                _time,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: done ? SaluteColors.textMuted : Colors.black87,
                ),
              ),
            ),
          ),
          Container(width: 1.5, color: const Color(0xFFE8E8E8)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.location.isNotEmpty ? event.location : event.profileName,
                          style: TextStyle(fontSize: 13, color: SaluteColors.textMuted),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          event.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            decoration: done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 14, color: SaluteColors.primaryGreen),
                            const SizedBox(width: 4),
                            Flexible(child: Text(
                              event.profileName,
                              style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
                            )),
                            if (event.reminderMinutesBefore != null) ...[
                              const SizedBox(width: 10),
                              Icon(Icons.alarm, size: 13, color: SaluteColors.terracotta),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        A11yTap(
                          hint: 'Tocá para cambiar el estado',
                          onTap: onToggleStatus,
                          child: _StatusBadge(status: event.status),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(color: SaluteColors.primaryGreen, shape: BoxShape.circle),
                        child: Icon(_typeIcons[event.type] ?? Icons.event_note_outlined, color: Colors.white, size: 18),
                      ),
                      if (!selecting) ...[
                        const SizedBox(height: 10),
                        const Icon(Icons.visibility_outlined, size: 20, color: SaluteColors.primaryGreen),
                      ],
                    ],
                  ),
                ],
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

// ─────────────────────────────────────────────────────────────────────────────
// BARRA DE SELECCIÓN MÚLTIPLE
// ─────────────────────────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final int count;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleAll;
  final VoidCallback onDelete;

  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.onClose,
    required this.onToggleAll,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFB03A3A);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancelar selección',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              count == 0 ? 'Elegí eventos' : (count == 1 ? '1 seleccionado' : '$count seleccionados'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
          ),
          TextButton(
            onPressed: onToggleAll,
            child: Text(
              allSelected ? 'Ninguno' : 'Todos',
              style: const TextStyle(color: SaluteColors.primaryGreen, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Eliminar seleccionados',
            onPressed: count == 0 ? null : onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: count == 0 ? SaluteColors.textMuted : red),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETALLE DE UN EVENTO (ver / editar / eliminar)
// ─────────────────────────────────────────────────────────────────────────────

enum _EventAction { edit, delete, toggleStatus }

const _typeLabelsLong = {
  AgendaEventType.turno: 'Turno',
  AgendaEventType.estudio: 'Estudio',
  AgendaEventType.vacuna: 'Vacuna',
  AgendaEventType.control: 'Control',
  AgendaEventType.medicacion: 'Medicación',
  AgendaEventType.otro: 'Otro',
};

String _longDate(DateTime d) =>
    '${_weekdayLabels[d.weekday - 1]} ${d.day} de ${_monthLabelsFull[d.month - 1]} de ${d.year}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _reminderText(int? minutes) {
  if (minutes == null) return 'Sin alarma';
  final known = AgendaEventFormScreen.reminderLabels[minutes];
  if (known != null) return known;
  if (minutes % 1440 == 0) return '${minutes ~/ 1440} día(s) antes';
  if (minutes % 60 == 0) return '${minutes ~/ 60} h antes';
  return '$minutes min antes';
}

class _EventDetailSheet extends StatelessWidget {
  final AgendaEvent event;
  const _EventDetailSheet({required this.event});

  @override
  Widget build(BuildContext context) {
    final done = event.status == AgendaEventStatus.completado;
    const red = Color(0xFFB03A3A);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: SaluteColors.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_typeIcons[event.type] ?? Icons.event_note_outlined, color: SaluteColors.primaryGreen),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.black87),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _typeLabelsLong[event.type] ?? 'Evento',
                        style: TextStyle(fontSize: 13, color: SaluteColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InfoLine(icon: Icons.person_outline, label: 'Perfil', value: event.profileName),
            _InfoLine(icon: Icons.event_outlined, label: 'Fecha', value: _longDate(event.date)),
            _InfoLine(icon: Icons.access_time, label: 'Hora', value: _hhmm(event.date)),
            _InfoLine(
              icon: Icons.location_on_outlined,
              label: 'Lugar',
              value: event.location.isNotEmpty ? event.location : 'Sin lugar indicado',
            ),
            _InfoLine(icon: Icons.alarm, label: 'Alarma', value: _reminderText(event.reminderMinutesBefore)),
            _InfoLine(icon: Icons.flag_outlined, label: 'Estado', value: _statusLabels[event.status] ?? ''),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, _EventAction.toggleStatus),
                icon: Icon(done ? Icons.radio_button_unchecked : Icons.check_circle_outline, size: 18),
                label: Text(done ? 'Marcar como pendiente' : 'Marcar como completado'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SaluteColors.primaryGreen,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: SaluteColors.primaryGreen.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _EventAction.edit),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(
                      backgroundColor: SaluteColors.primaryGreen,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, _EventAction.delete),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: red,
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide(color: red.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoLine({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: SaluteColors.primaryGreen),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: SaluteColors.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BADGE DE ESTADO (tocable: alterna Pendiente <-> Completado)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final AgendaEventStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final done = status == AgendaEventStatus.completado;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: done
            ? SaluteColors.primaryGreen.withValues(alpha: 0.15)
            : SaluteColors.lightGreen.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SaluteColors.primaryGreen.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 13,
            color: SaluteColors.primaryGreen,
          ),
          const SizedBox(width: 5),
          Text(
            _statusLabels[status] ?? '',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SaluteColors.primaryGreen),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ESTADO VACÍO
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final VoidCallback onAdd;
  const _EmptyState({required this.message, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_outlined, size: 44, color: SaluteColors.textMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: SaluteColors.textMuted, fontSize: 14)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, color: SaluteColors.primaryGreen),
              label: const Text('Agregar turno', style: TextStyle(color: SaluteColors.primaryGreen)),
            ),
          ],
        ),
      ),
    );
  }
}