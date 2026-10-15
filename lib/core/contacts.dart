import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/sos_contact.dart';
import 'package:saluteapp/core/services/sos_contact_service.dart';

/// Acciones del contacto SOS compartidas entre el Diario ([EmergenciaCard])
/// y el Perfil: elegir el contacto desde la agenda del teléfono y llamarlo.
/// Así las dos pantallas se comportan exactamente igual.
class SosActions {
  SosActions._();

  /// Número apto para marcar: deja solo dígitos y un `+` inicial.
  static String dialable(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return trimmed.startsWith('+') ? '+$digits' : digits;
  }

  /// Abre el marcador del teléfono con el número del contacto.
  static Future<void> call(BuildContext context, SosContact contacto) async {
    final number = dialable(contacto.phoneNumber);
    final messenger = ScaffoldMessenger.of(context);
    if (number.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Este contacto no tiene un número válido.'),
          backgroundColor: SaluteColors.urgent,
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: number);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (e) {
      debugPrint('Error al llamar al contacto SOS: $e');
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('No se pudo iniciar la llamada.'),
        backgroundColor: SaluteColors.urgent,
      ),
    );
  }

  /// Deja elegir un contacto de la agenda y lo guarda como SOS. Devuelve el
  /// contacto guardado, o `null` si se canceló o falló (ya avisó con un
  /// SnackBar). No hace falta refrescar nada a mano: los streams de
  /// [SosContactService] traen el cambio solos.
  static Future<SosContact?> pickAndSave(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    void aviso(String texto, {Color color = SaluteColors.urgent}) {
      messenger.showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: color),
      );
    }

    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status != PermissionStatus.granted) {
        aviso('Permiso denegado para acceder a los contactos.');
        return null;
      }

      final contact = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.phone},
      );
      if (contact == null) return null;

      final phone = contact.phones.isNotEmpty
          ? contact.phones.first.number
          : '';
      if (phone.isEmpty) {
        aviso('Ese contacto no tiene un número de teléfono.');
        return null;
      }

      final rawName = contact.displayName;
      final sosContact = SosContact(
        displayName: (rawName != null && rawName.isNotEmpty)
            ? rawName
            : 'Sin nombre',
        phoneNumber: phone,
      );
      try {
        await SosContactService.instance.saveSosContact(sosContact);
        aviso(
          'Contacto SOS configurado: ${sosContact.displayName}',
          color: SaluteColors.primaryGreen,
        );
        return sosContact;
      } catch (e) {
        debugPrint('Error al guardar contacto SOS: $e');
        aviso('No se pudo guardar el contacto. Revisá tu conexión.');
        return null;
      }
    } catch (e) {
      debugPrint('Error al seleccionar contacto SOS: $e');
      return null;
    }
  }
}

/// Card de "Protocolo de Emergencia": deja elegir un contacto SOS desde
/// la agenda del teléfono, lo persiste en Firestore (`users/{uid}.sosContact`,
/// ver [SosContactService]) y una vez configurado muestra un acceso
/// directo para llamarlo.
class EmergenciaCard extends StatefulWidget {
  const EmergenciaCard({super.key});

  @override
  State<EmergenciaCard> createState() => _EmergenciaCardState();
}

class _EmergenciaCardState extends State<EmergenciaCard> {
  bool _cargando = false;
  bool _cargandoInicial = true;
  SosContact? _contacto;
  StreamSubscription<SosContact?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = SosContactService.instance.watchSosContact().listen(
      (contacto) {
        if (!mounted) return;
        setState(() {
          _contacto = contacto;
          _cargandoInicial = false;
        });
      },
      onError: (_) {
        // Sin usuario logueado o sin conexión la primera vez: mostramos
        // el estado "sin contacto" en vez de spinnear para siempre.
        if (mounted) setState(() => _cargandoInicial = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _seleccionarContactoSOS() async {
    setState(() => _cargando = true);
    try {
      await SosActions.pickAndSave(context);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _llamarContacto() async {
    final contacto = _contacto;
    if (contacto == null) return;
    await SosActions.call(context, contacto);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SaluteColors.lightGreen.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: SaluteColors.lightGreen.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.emergency_outlined,
            color: SaluteColors.primaryGreen,
            size: 32,
          ),
          const SizedBox(height: 16),
          const Text(
            'Protocolo de Emergencia',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Configura tus contactos de confianza y tu grupo sanguíneo para acceso rápido en pantalla de bloqueo.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          if (_cargandoInicial)
            const SizedBox(
              height: 50,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_contacto != null)
            _ContactoSosRow(
              contacto: _contacto!,
              onLlamar: _llamarContacto,
              onCambiar: _cargando ? null : _seleccionarContactoSOS,
              cargando: _cargando,
            )
          else
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _cargando ? null : _seleccionarContactoSOS,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _cargando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'CONFIGURAR S.O.S.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fila que muestra el contacto SOS ya configurado, con acceso directo
/// para llamar y un botón secundario para cambiarlo.
class _ContactoSosRow extends StatelessWidget {
  final SosContact contacto;
  final VoidCallback onLlamar;
  final VoidCallback? onCambiar;
  final bool cargando;

  const _ContactoSosRow({
    required this.contacto,
    required this.onLlamar,
    required this.onCambiar,
    required this.cargando,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: SaluteColors.primaryGreen.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: SaluteColors.primaryGreen.withValues(alpha: 0.15),
            child: Text(
              contacto.displayName.isNotEmpty
                  ? contacto.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: SaluteColors.primaryGreen,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contacto.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  contacto.phoneNumber,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (cargando)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (onCambiar != null)
            IconButton(
              onPressed: onCambiar,
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: Colors.grey[500],
              tooltip: 'Cambiar contacto',
            ),
          Container(
            decoration: const BoxDecoration(
              color: SaluteColors.primaryGreen,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: cargando ? null : onLlamar,
              icon: const Icon(Icons.call, color: Colors.white, size: 20),
              tooltip: 'Llamar a ${contacto.displayName}',
            ),
          ),
        ],
      ),
    );
  }
}
