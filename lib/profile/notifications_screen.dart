import 'package:saluteapp/components/a11y_tap.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/services/app_settings_service.dart';
import 'package:saluteapp/core/services/notifications_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Esta pantalla ya no muestra notificaciones de utilería: las genera
// NotificationsService a partir de agenda, medicación, botiquín y perfiles
// reales (ver ese archivo para el detalle de cada regla).
//
// Lo que NO hace esto: no son push notifications (no llegan si la app está
// cerrada) ni los avisos por SMS/WhatsApp del "sistema de alerta familiar"
// del proyecto — ambos requieren integrar un servicio externo (FCM,
// Twilio, etc.) y quedan pendientes.
//
// El estado de "leída"/"descartada" no existe como documento en Firestore
// (no hay una notificación real que marcar), así que se guarda en el
// dispositivo con `shared_preferences` — se mantiene entre aperturas de la
// app en el mismo dispositivo, pero no se sincroniza entre dispositivos.
// Requiere agregar el paquete `shared_preferences` al pubspec si todavía
// no está.
// ─────────────────────────────────────────────────────────────────────────────

const _kReadIdsKey = kNotificationsReadIdsKey;
const _kDismissedIdsKey = kNotificationsDismissedIdsKey;

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const NotificationsScreen({super.key, this.onBack});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<AppNotification> _notifications = [];
  Set<String> _readIds = {};
  Set<String> _dismissedIds = {};
  bool _showOnlyUnread = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final readList = prefs.getStringList(_kReadIdsKey) ?? const [];
      final dismissedList = prefs.getStringList(_kDismissedIdsKey) ?? const [];
      final notifications = await NotificationsService.instance.generate();
      if (!mounted) return;
      setState(() {
        _readIds = readList.toSet();
        _dismissedIds = dismissedList.toSet();
        _notifications = notifications;
        _loading = false;
      });
      _publishBadge();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<AppNotification> get _visibleNotifications {
    var list = _notifications.where((n) => !_dismissedIds.contains(n.id));
    if (_showOnlyUnread) {
      list = list.where((n) => !_readIds.contains(n.id));
    }
    return list.toList();
  }

  Future<void> _persistReadIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kReadIdsKey, _readIds.toList());
  }

  Future<void> _persistDismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDismissedIdsKey, _dismissedIds.toList());
  }

  /// Actualiza el puntito del Home con el estado actual de esta pantalla,
  /// así se apaga (o se prende) apenas cambia, sin esperar a que el Home
  /// se reconstruya.
  void _publishBadge() {
    NotificationsService.instance.setUnread(
      NotificationsService.badgeCount(_notifications, _readIds, _dismissedIds),
    );
  }

  void _markAsRead(String id) {
    setState(() => _readIds.add(id));
    _publishBadge();
    _persistReadIds();
  }

  void _dismiss(String id) {
    setState(() => _dismissedIds.add(id));
    _publishBadge();
    _persistDismissedIds();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleNotifications;
    final unreadCount = _notifications.where((n) => !_dismissedIds.contains(n.id) && !_readIds.contains(n.id)).length;

    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Notificaciones',
              onBack: widget.onBack ?? () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _loading ? 'Cargando...' : '$unreadCount sin leer · ${visible.length} en total',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SaluteColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  A11yTap(
                    onTap: () => setState(() => _showOnlyUnread = !_showOnlyUnread),
                    label: _showOnlyUnread ? 'Filtro: solo sin leer' : 'Filtro: todas',
                    hint: 'Tocar para cambiar el filtro',
                    selected: _showOnlyUnread,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showOnlyUnread ? SaluteColors.primaryGreen.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showOnlyUnread ? SaluteColors.primaryGreen : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        _showOnlyUnread ? 'Sin leer' : 'Todo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _showOnlyUnread ? SaluteColors.primaryGreen : SaluteColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Aviso cuando el switch de Notificaciones está apagado.
            ListenableBuilder(
              listenable: AppSettingsService.instance,
              builder: (context, _) {
                if (AppSettingsService.instance.notificationsEnabled) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SaluteColors.brownOrange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: SaluteColors.brownOrange.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notifications_off_outlined, size: 20, color: SaluteColors.brownOrange),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Las notificaciones están desactivadas: no recibís avisos en el teléfono ni ves el punto de novedades. Podés activarlas en Configuración.',
                            style: TextStyle(fontSize: 13, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Expanded(child: _buildBody(visible)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<AppNotification> visible) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: SaluteColors.primaryGreen));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudieron cargar las notificaciones: $_error', textAlign: TextAlign.center, style: TextStyle(color: SaluteColors.textMuted)),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(
              height: 400,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.notifications_none_outlined, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      _showOnlyUnread ? 'No hay notificaciones sin leer' : 'No hay notificaciones por ahora',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SaluteColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final n = visible[index];
          return _NotificationCard(
            notification: n,
            isRead: _readIds.contains(n.id),
            onMarkAsRead: () => _markAsRead(n.id),
            onDelete: () => _dismiss(n.id),
          );
        },
      ),
    );
  }
}

String _relativeLabel(DateTime date, NotificationKind kind) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;

  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  if (diff > 1) return 'En $diff días';
  final overdue = -diff;
  return 'Hace $overdue día${overdue == 1 ? '' : 's'}';
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final bool isRead;
  final VoidCallback onMarkAsRead;
  final VoidCallback onDelete;

  const _NotificationCard({
    required this.notification,
    required this.isRead,
    required this.onMarkAsRead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notification.id),
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: SaluteColors.danger, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: isRead ? null : onMarkAsRead,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isRead ? null : Border.all(color: notification.color.withValues(alpha: 0.3), width: 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: notification.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(notification.icon, color: notification.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isRead)
                          Semantics(label: 'No leída', child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: notification.color, shape: BoxShape.circle),
                          )),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.message,
                      style: TextStyle(fontSize: 13, color: SaluteColors.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _relativeLabel(notification.date, notification.kind),
                      style: TextStyle(fontSize: 12, color: SaluteColors.textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              A11yTap(
                label: 'Descartar este aviso',
                onTap: onDelete,
                child: Icon(Icons.close, size: 20, color: SaluteColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
