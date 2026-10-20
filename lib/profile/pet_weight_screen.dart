import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/vital_entry.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/core/services/vitals_service.dart';

/// "4,35 kg" (2 decimales bajo los 10 kg, 1 desde ahí). Lo comparten esta
/// pantalla y la tarjeta de peso del perfil, para que muestren lo mismo.
String formatPetWeightKg(double v) =>
    '${v.toStringAsFixed(v < 10 ? 2 : 1).replaceAll('.', ',')} kg';

/// Historial de peso de una mascota.
///
/// Cada registro se guarda en `vitals` (solo con `weightKg`, mismo patrón
/// que BiometricsScreen) y el último valor se copia a la ficha clínica
/// (`datos_clinicos/ficha`), que es lo que muestran la ficha y el PDF.
class PetWeightScreen extends StatefulWidget {
  final FamilyProfile profile;
  const PetWeightScreen({super.key, required this.profile});

  @override
  State<PetWeightScreen> createState() => _PetWeightScreenState();
}

class _PetWeightScreenState extends State<PetWeightScreen> {
  late final Stream<List<VitalEntry>> _stream = VitalsService.instance.watchForProfile(widget.profile.id);

  String _fmtKg(double v) => formatPetWeightKg(v);

  /// Solo quien administra la mascota puede cargar o borrar pesos (es lo que
  /// exigen las reglas); quien la ve por acceso compartido solo lee.
  bool get _canEdit => widget.profile.ownerUid == FirebaseAuth.instance.currentUser?.uid;

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addWeight() async {
    final kg = await showDialog<double>(
      context: context,
      builder: (_) => _WeightDialog(petName: widget.profile.name),
    );
    if (kg == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await VitalsService.instance.addEntry(
        VitalEntry(
          id: '',
          ownerUid: uid,
          profileId: widget.profile.id,
          date: DateTime.now(),
          weightKg: kg,
        ),
      );
      await ProfileService.instance.setWeightKg(widget.profile.id, kg);
    } catch (_) {
      _snack('No se pudo guardar el peso. Probá de nuevo.');
    }
  }

  /// [weights] viene ordenado del más reciente al más antiguo.
  Future<void> _delete(VitalEntry entry, List<VitalEntry> weights) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar registro'),
        content: Text('¿Borrar el peso de ${_fmtKg(entry.weightKg!)} del ${_fmtDate(entry.date)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await VitalsService.instance.deleteEntry(entry.id);
      // Si era el último, la ficha pasa a mostrar el registro anterior.
      if (weights.isNotEmpty && weights.first.id == entry.id && weights.length > 1) {
        await ProfileService.instance.setWeightKg(widget.profile.id, weights[1].weightKg!);
      }
    } catch (_) {
      _snack('No se pudo borrar el registro.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: 'Peso', onBack: () => Navigator.maybePop(context)),
            Expanded(
              child: StreamBuilder<List<VitalEntry>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Center(child: Text('No se pudo cargar el historial de peso.'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final weights = snap.data!.where((e) => e.weightKg != null).toList();
                  final latest = weights.isNotEmpty ? weights.first.weightKg : widget.profile.weightKg;
                  final delta = weights.length >= 2 ? weights[0].weightKg! - weights[1].weightKg! : null;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: SaluteColors.cardBeige,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PESO ACTUAL · ${widget.profile.name.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: SaluteColors.textMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              latest != null ? _fmtKg(latest) : 'Sin registrar',
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.black87),
                            ),
                            if (weights.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Registrado el ${_fmtDate(weights.first.date)}'
                                '${delta != null ? ' · ${delta >= 0 ? '+' : '−'}${delta.abs().toStringAsFixed(2).replaceAll('.', ',')} kg vs. el registro anterior' : ''}',
                                style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_canEdit) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _addWeight,
                            style: FilledButton.styleFrom(
                              backgroundColor: SaluteColors.primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Registrar peso'),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      const Text(
                        'Historial',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      if (weights.isEmpty)
                        Text(
                          _canEdit
                              ? 'Todavía no hay registros. Cargá el primero con el botón de arriba.'
                              : 'Todavía no hay registros.',
                          style: TextStyle(fontSize: 13, color: SaluteColors.textMuted),
                        )
                      else
                        for (final e in weights)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.monitor_weight_outlined, color: SaluteColors.primaryGreen),
                            title: Text(_fmtKg(e.weightKg!), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(_fmtDate(e.date)),
                            trailing: _canEdit
                                ? IconButton(
                                    tooltip: 'Borrar',
                                    icon: Icon(Icons.delete_outline, color: SaluteColors.textMuted),
                                    onPressed: () => _delete(e, weights),
                                  )
                                : null,
                          ),
                    ],
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

/// Diálogo para cargar el peso. Tiene su propio State para poder liberar el
/// controller sin problemas cuando se cierra.
class _WeightDialog extends StatefulWidget {
  final String petName;
  const _WeightDialog({required this.petName});

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (v == null || v < 0.05 || v > 150) {
      setState(() => _error = 'Ingresá un peso válido (0,05 a 150 kg)');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Peso de ${widget.petName}'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Ej: 12,5',
          suffixText: 'kg',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}
