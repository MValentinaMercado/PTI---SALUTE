import 'package:flutter/material.dart';

/// Navigator global de la app. Permite abrir pantallas desde fuera del
/// árbol de widgets, por ejemplo cuando el usuario toca una notificación
/// de medicación (ver MedicationReminderService).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
