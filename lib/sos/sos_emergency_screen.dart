import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:saluteapp/core/contacts.dart';
import 'package:saluteapp/core/models/sos_contact.dart';
import 'package:saluteapp/core/services/sos_alert_service.dart';
import 'package:saluteapp/sos/sos_button.dart' show kSosRed;
import 'package:saluteapp/sos/sos_controller.dart';

/// Pantalla de emergencia: se abre al activar el SOS y muestra, en grande y
/// sin depender solo del color, el estado real del envío, la ubicación usada
/// y las acciones disponibles. No hay mapa, seguimiento ni historial.
class SosEmergencyScreen extends StatelessWidget {
  const SosEmergencyScreen({super.key});

  Future<void> _finish(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Finalizar la emergencia?'),
        content: const Text(
          'Se cierra esta pantalla y se descarta la ubicación usada. '
          'Tu contacto no recibe ningún aviso por esto.',
          style: TextStyle(fontSize: 17, height: 1.4),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 52), child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sí, finalizar', style: TextStyle(fontSize: 17)),
            ),
          ),
          ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 52), child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Seguir en emergencia', style: TextStyle(fontSize: 17)),
            ),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      // Primero se cierra la pantalla (pop() no consulta PopScope) y recién
      // después se limpia el estado. Antes se usaba maybePop(), que quedaba
      // bloqueado por canPop:false y la pantalla no se cerraba nunca.
      final nav = Navigator.of(context);
      SosController.instance.finish();
      if (nav.canPop()) nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SosController.instance;
    return ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final contact = c.contact;
          final result = c.result;
          return PopScope(
            canPop: !c.isActive,
            child: Scaffold(
            backgroundColor: const Color(0xFFFFF4F2),
            body: SafeArea(
              child: Column(
                children: [
                  _Banner(activatedAt: c.activatedAt),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _StatusCard(phase: c.phase, result: result, contact: contact),
                          const SizedBox(height: 12),
                          if (c.phase == SosPhase.done && result?.status != SosSendStatus.noContact)
                            _LocationCard(result: result),
                          if (c.phase == SosPhase.done && result?.status != SosSendStatus.noContact)
                            const SizedBox(height: 12),
                          if (c.phase == SosPhase.done) _Actions(controller: c),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 56), child: OutlinedButton.icon(
                        onPressed: () => _finish(context),
                        icon: const Icon(Icons.close),
                        label: const Text('Finalizar emergencia',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
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

class _Banner extends StatelessWidget {
  final DateTime? activatedAt;
  const _Banner({required this.activatedAt});

  @override
  Widget build(BuildContext context) {
    final t = activatedAt;
    final hora = t == null
        ? ''
        : ' · desde las ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Semantics(
      header: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: kSosRed,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'EMERGENCIA ACTIVA$hora',
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? body;
  final Widget? trailing;
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    this.body,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900, color: color, height: 1.25)),
                ),
              ],
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!,
                  style: const TextStyle(fontSize: 17, height: 1.4, color: Colors.black87)),
            ],
            if (trailing != null) ...[const SizedBox(height: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

// Colores de estado con contraste >= 4,5:1 sobre blanco, y siempre
// acompañados por ícono + texto (no dependen solo del color).
const _kOk = Color(0xFF1B5E20);
const _kWarn = Color(0xFF8A4B00);
const _kErr = Color(0xFFB3261E);

class _StatusCard extends StatelessWidget {
  final SosPhase phase;
  final SosAlertResult? result;
  final SosContact? contact;
  const _StatusCard({required this.phase, required this.result, required this.contact});

  @override
  Widget build(BuildContext context) {
    if (phase != SosPhase.done || result == null) {
      return const _InfoCard(
        icon: Icons.hourglass_top,
        color: _kWarn,
        title: 'Enviando la alerta…',
        body: 'Buscando tu ubicación y mandando el mensaje a tu contacto.',
        trailing: LinearProgressIndicator(minHeight: 6),
      );
    }
    final r = result!;
    final name = contact?.displayName ?? 'tu contacto';
    switch (r.status) {
      case SosSendStatus.sent:
        return _InfoCard(
          icon: Icons.check_circle,
          color: _kOk,
          title: 'Alerta ENVIADA por SMS a $name',
          body: 'El mensaje ya salió de tu teléfono. Ahora podés llamarlo.',
        );
      case SosSendStatus.noContact:
        return _InfoCard(
          icon: Icons.person_add_alt_1,
          color: _kErr,
          title: 'No hay contacto de emergencia',
          body: 'No se envió ninguna alerta. Primero tenés que elegir a quién avisar.',
          trailing: ConstrainedBox(constraints: const BoxConstraints(minHeight: 56), child: FilledButton.icon(
              onPressed: () async {
                final saved = await SosActions.pickAndSave(context);
                if (saved != null) SosController.instance.retry();
              },
              icon: const Icon(Icons.contacts),
              label: const Text('Elegir contacto de emergencia',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
        );
      case SosSendStatus.notAutomatic:
        return const _InfoCard(
          icon: Icons.error_outline,
          color: _kErr,
          title: 'La alerta NO fue enviada',
          body: 'Este teléfono no permite enviar el mensaje automáticamente. '
              'Llamá a tu contacto, o mandá el mensaje a mano con el botón de abajo.',
        );
      case SosSendStatus.failed:
        return _InfoCard(
          icon: Icons.error,
          color: _kErr,
          title: 'La alerta NO se pudo enviar',
          body: _failureText(r.failure),
        );
    }
  }

  String _failureText(SosFailure? f) {
    switch (f) {
      case SosFailure.noService:
        return 'No hay señal de telefonía. Probá moverte a un lugar abierto. '
            'Si tenés internet, podés probar por WhatsApp. La llamada puede '
            'funcionar igual si hay señal.';
      case SosFailure.radioOff:
        return 'El teléfono está en modo avión o sin red móvil. Desactivalo y '
            'reintentá.';
      case SosFailure.noPermission:
        return 'La app no tiene permiso para enviar SMS. Activalo en los ajustes '
            'de la app y reintentá.';
      case SosFailure.invalidNumber:
        return 'El número del contacto no es válido. Cambiá el contacto de emergencia.';
      case SosFailure.other:
      case null:
        return 'Ocurrió un problema al enviar el mensaje. Reintentá o llamá a tu contacto.';
    }
  }
}

class _LocationCard extends StatelessWidget {
  final SosAlertResult? result;
  const _LocationCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final loc = result?.location;
    if (loc != null && !loc.isLastKnown) {
      return _InfoCard(
        icon: Icons.my_location,
        color: _kOk,
        title: 'Ubicación ACTUAL incluida',
        body: loc.accuracyMeters > 0
            ? 'Precisión aproximada: ${loc.accuracyMeters.round()} m.'
            : null,
      );
    }
    if (loc != null && loc.isLastKnown) {
      return _InfoCard(
        icon: Icons.history,
        color: _kWarn,
        title: 'ÚLTIMA ubicación conocida (${loc.ageLabel})',
        body: 'No pudimos obtener tu ubicación actual. Se envió la última que '
            'conoce el teléfono y se aclaró en el mensaje que puede no ser la actual.',
      );
    }
    return _InfoCard(
      icon: Icons.location_off,
      color: _kErr,
      title: 'Sin ubicación en el mensaje',
      body: _issueText(result?.locationIssue),
      trailing: _issueAction(result?.locationIssue),
    );
  }

  String _issueText(SosLocationIssue? i) {
    switch (i) {
      case SosLocationIssue.disabledInApp:
        return 'Desactivaste los Servicios de Ubicación en Configuración de la app.';
      case SosLocationIssue.permissionDenied:
        return 'El teléfono no le dio permiso de ubicación a la app.';
      case SosLocationIssue.serviceOff:
        return 'El GPS del teléfono está apagado.';
      case SosLocationIssue.unavailable:
      case null:
        return 'No se pudo obtener tu posición a tiempo. Avisá dónde estás cuando lo llames.';
    }
  }

  Widget? _issueAction(SosLocationIssue? i) {
    switch (i) {
      case SosLocationIssue.permissionDenied:
        return ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: OutlinedButton(
            onPressed: Geolocator.openAppSettings,
            child: const Text('Abrir ajustes de la app', style: TextStyle(fontSize: 16)),
          ),
        );
      case SosLocationIssue.serviceOff:
        return ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: OutlinedButton(
            onPressed: Geolocator.openLocationSettings,
            child: const Text('Encender el GPS', style: TextStyle(fontSize: 16)),
          ),
        );
      default:
        return null;
    }
  }
}

class _Actions extends StatelessWidget {
  final SosController controller;
  const _Actions({required this.controller});

  @override
  Widget build(BuildContext context) {
    final contact = controller.contact;
    final r = controller.result;
    final hasContact = contact != null && contact.phoneNumber.trim().isNotEmpty;
    final failed = r != null && r.status != SosSendStatus.sent && r.status != SosSendStatus.noContact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasContact)
          ConstrainedBox(constraints: const BoxConstraints(minHeight: 76), child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kOk,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () => SosActions.call(context, contact),
              icon: const Icon(Icons.call, size: 32),
              label: Text(
                'LLAMAR a ${contact.displayName}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        if (failed) ...[
          const SizedBox(height: 12),
          ConstrainedBox(constraints: const BoxConstraints(minHeight: 56), child: FilledButton.icon(
              onPressed: controller.retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar envío del SMS',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
        if (hasContact && controller.whatsAppAvailable && r != null && r.message.isNotEmpty) ...[
          const SizedBox(height: 12),
          ConstrainedBox(constraints: const BoxConstraints(minHeight: 56), child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await SosAlertService.instance
                    .openWhatsApp(contact: contact, message: r.message);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
                  );
                }
              },
              icon: const Icon(Icons.chat),
              label: Text(
                failed ? 'Probar por WhatsApp (necesita internet)' : 'Avisar también por WhatsApp',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'WhatsApp se abre con el mensaje listo: tenés que tocar "Enviar".',
              style: TextStyle(fontSize: 14, color: Color(0xFF5F6368)),
            ),
          ),
        ],
        if (failed && hasContact && r!.message.isNotEmpty) ...[
          const SizedBox(height: 12),
          ConstrainedBox(constraints: const BoxConstraints(minHeight: 56), child: OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(
                    'sms:${SosAlertService.dialable(contact.phoneNumber)}?body=${Uri.encodeComponent(r.message)}'),
              ),
              icon: const Icon(Icons.sms),
              label: const Text('Abrir SMS con el mensaje',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }
}
