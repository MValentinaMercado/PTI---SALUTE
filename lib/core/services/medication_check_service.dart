import 'package:flutter/foundation.dart';
import 'package:saluteapp/core/models/dose_log.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/dose_log_service.dart';
import 'package:saluteapp/core/services/medicine_item_service.dart';

/// Marcar una toma como tomada / no tomada / sin marcar, y mantener el
/// botiquín al día: si la medicación está vinculada a un ítem, marcar
/// "tomada" descuenta `unitsPerDose` unidades, y deshacerlo las devuelve.
class MedicationCheckService {
  MedicationCheckService._();
  static final MedicationCheckService instance = MedicationCheckService._();

  /// [status] null = deshacer (volver a "pendiente"). [previous] es el
  /// estado que la UI ya conocía; se pasa en vez de leerlo de Firestore
  /// para que funcione también sin conexión.
  ///
  /// Devuelve el stock que quedó en el botiquín si se lo modificó, o
  /// null si no había nada que ajustar.
  Future<int?> mark({
    required String profileId,
    required Medication medication,
    required DateTime scheduledAt,
    required DoseStatus? status,
    required DoseStatus? previous,
  }) async {
    if (status == previous) return null;

    if (status == null) {
      await DoseLogService.instance.clear(profileId, medication.id, scheduledAt);
    } else {
      await DoseLogService.instance.save(
        profileId,
        DoseLog(
          id: DoseLog.idFor(medication.id, scheduledAt),
          medicationId: medication.id,
          medicationName: medication.name,
          scheduledAt: scheduledAt,
          status: status,
        ),
      );
    }

    final itemId = medication.botiquinItemId;
    if (itemId == null || itemId.isEmpty) return null;

    var delta = 0;
    if (status == DoseStatus.taken && previous != DoseStatus.taken) delta = -medication.unitsPerDose;
    if (status != DoseStatus.taken && previous == DoseStatus.taken) delta = medication.unitsPerDose;
    if (delta == 0) return null;

    try {
      return await MedicineItemService.instance.adjustStock(itemId, delta);
    } catch (e) {
      // Marcar la toma ya quedó guardado; que el botiquín no se haya
      // podido actualizar (sin conexión, ítem borrado) no debe bloquearlo.
      debugPrint('MedicationCheckService: no se pudo ajustar el botiquín $itemId. $e');
      return null;
    }
  }
}
