import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/sos_contact.dart';
import 'package:saluteapp/core/services/sos_contact_service.dart';
import 'package:saluteapp/core/services/sos_sms_sender.dart';

/// Acciones del contacto SOS que usa el Perfil (tarjeta "Protocolo de
/// Emergencia"): elegir el contacto desde la agenda del teléfono y llamarlo.
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
          backgroundColor: SaluteColors.danger,
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
        backgroundColor: SaluteColors.danger,
      ),
    );
  }

  /// Deja elegir un contacto de la agenda y lo guarda como SOS. Devuelve el
  /// contacto guardado, o `null` si se canceló o falló (ya avisó con un
  /// SnackBar). No hace falta refrescar nada a mano: los streams de
  /// [SosContactService] traen el cambio solos.
  static Future<SosContact?> pickAndSave(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    void aviso(String texto, {Color color = SaluteColors.danger}) {
      messenger.showSnackBar(SnackBar(content: Text(texto), backgroundColor: color));
    }

    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted) {
        aviso('Permiso denegado para acceder a los contactos.');
        return null;
      }

      final contact = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.phone},
      );
      if (contact == null) return null;

      final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
      if (phone.isEmpty) {
        aviso('Ese contacto no tiene un número de teléfono.');
        return null;
      }

      final rawName = contact.displayName;
      final sosContact = SosContact(
        displayName: (rawName != null && rawName.isNotEmpty) ? rawName : 'Sin nombre',
        phoneNumber: phone,
      );
      try {
        await SosContactService.instance.saveSosContact(sosContact);
        aviso('Contacto SOS configurado: ${sosContact.displayName}', color: SaluteColors.primaryGreen);
        // Se piden ahora (con calma) los permisos que el SOS necesita, para
        // no mostrar diálogos en medio de una emergencia.
        await SosSmsSender.instance.requestPermission();
        try {
          final p = await Geolocator.checkPermission();
          if (p == LocationPermission.denied) await Geolocator.requestPermission();
        } catch (_) {}
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
