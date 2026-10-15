import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/services/vaccine_catalog.dart';

/// Piezas visuales compartidas por las pantallas del carné de vacunación.

String fmtVaccineDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class VaccineLabel extends StatelessWidget {
  final String text;
  const VaccineLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
      );
}

InputDecoration vaccineInputDecoration(String hint) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(Colors.grey.shade200),
    enabledBorder: border(Colors.grey.shade200),
    focusedBorder: border(SaluteColors.primaryGreen, 1.5),
  );
}

/// Campo "tocar para elegir fecha", con botón opcional para limpiarla.
class VaccineDateField extends StatelessWidget {
  final DateTime? value;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const VaccineDateField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 18, color: SaluteColors.primaryGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value != null ? fmtVaccineDate(value!) : placeholder,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: value != null ? Colors.black87 : Colors.grey[400],
                ),
              ),
            ),
            if (value != null && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded, size: 18, color: Colors.grey[500]),
              ),
          ],
        ),
      ),
    );
  }
}

Color vaccineStatusColor(VaccineStatus s) {
  switch (s) {
    case VaccineStatus.aplicada:
      return SaluteColors.primaryGreen;
    case VaccineStatus.proxima:
      return SaluteColors.darkGreen;
    case VaccineStatus.pendiente:
      return SaluteColors.brownOrange;
    case VaccineStatus.verificar:
      return SaluteColors.terracotta;
    case VaccineStatus.sinRegistro:
    case VaccineStatus.noCorresponde:
      return Colors.grey.shade600;
  }
}

class VaccineStatusChip extends StatelessWidget {
  final VaccineStatus status;
  const VaccineStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = vaccineStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
    );
  }
}
