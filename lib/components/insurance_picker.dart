import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/services/insurance_service.dart';

/// Abre el selector de obra social (hoja inferior).
///
/// Devuelve:
///  - `null`  → el usuario cerró el selector sin elegir (no hay que guardar nada);
///  - `''`    → eligió "Sin obra social / Particular";
///  - cualquier otro texto → el nombre elegido (de la lista o agregado a mano).
///
/// Lo usan Configuración y el formulario de perfil, así los dos ofrecen
/// exactamente las mismas opciones.
Future<String?> showInsurancePicker(BuildContext context, {required String current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _InsurancePickerSheet(current: current),
  );
}

class _InsurancePickerSheet extends StatefulWidget {
  final String current;
  const _InsurancePickerSheet({required this.current});

  @override
  State<_InsurancePickerSheet> createState() => _InsurancePickerSheetState();
}

class _InsurancePickerSheetState extends State<_InsurancePickerSheet> {
  List<String> _custom = const [];
  bool _loadingCustom = true;

  @override
  void initState() {
    super.initState();
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    var custom = const <String>[];
    try {
      custom = await InsuranceService.instance.fetchCustom();
    } catch (_) {
      // Si no se pueden leer las agregadas a mano, igual se muestra la
      // lista común: no bloqueamos el selector por eso.
    }
    if (!mounted) return;
    setState(() {
      _custom = custom;
      _loadingCustom = false;
    });
  }

  /// Lista común + agregadas por el usuario + la que ya tenga elegida (por
  /// si vino de otro dispositivo), sin repetidas (ignora mayúsculas) y
  /// ordenadas alfabéticamente.
  List<String> _options() {
    final seen = <String>{};
    final result = <String>[];
    for (final name in [
      ...kCommonInsurances,
      ..._custom,
      if (widget.current.isNotEmpty) widget.current,
    ]) {
      if (seen.add(name.toLowerCase())) result.add(name);
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<void> _addCustom() async {
    final typed = await showDialog<String>(
      context: context,
      builder: (_) => const _AddInsuranceDialog(),
    );
    if (typed == null) return;
    final clean = normalizeInsuranceName(typed);
    if (clean.isEmpty) return;

    // Si ya existe (sin importar mayúsculas), se elige esa en vez de duplicarla.
    for (final existing in _options()) {
      if (existing.toLowerCase() == clean.toLowerCase()) {
        if (mounted) Navigator.pop(context, existing);
        return;
      }
    }

    try {
      await InsuranceService.instance.addCustom(clean);
    } catch (_) {
      // Si no se pudo guardar en la lista personal, igual se la asignamos
      // al perfil: lo importante es la selección.
    }
    if (mounted) Navigator.pop(context, clean);
  }

  @override
  Widget build(BuildContext context) {
    final options = _options();
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    final currentLower = widget.current.toLowerCase();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Obra social', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Elegí una de la lista o agregá la tuya.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
            if (_loadingCustom) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _OptionTile(
                    label: 'Sin obra social / Particular',
                    selected: widget.current.isEmpty,
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  for (final name in options)
                    _OptionTile(
                      label: name,
                      selected: name.toLowerCase() == currentLower,
                      onTap: () => Navigator.pop(context, name),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _addCustom,
                  icon: const Icon(Icons.add, color: SaluteColors.primaryGreen),
                  label: const Text(
                    'Agregar otra obra social',
                    style: TextStyle(color: SaluteColors.primaryGreen, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: SaluteColors.primaryGreen),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          color: selected ? SaluteColors.primaryGreen : Colors.black87,
        ),
      ),
      trailing: selected ? const Icon(Icons.check_circle, color: SaluteColors.primaryGreen) : null,
      onTap: onTap,
    );
  }
}

/// Diálogo para tipear una obra social que no está en la lista. Es un
/// StatefulWidget propio para que el controller se libere recién cuando el
/// diálogo termina de cerrarse (liberarlo antes rompe la animación de salida).
class _AddInsuranceDialog extends StatefulWidget {
  const _AddInsuranceDialog();

  @override
  State<_AddInsuranceDialog> createState() => _AddInsuranceDialogState();
}

class _AddInsuranceDialogState extends State<_AddInsuranceDialog> {
  final _controller = TextEditingController();

  bool get _valid => normalizeInsuranceName(_controller.text).length >= 2;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_valid) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar obra social'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: kInsuranceNameMaxLength,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Nombre de la obra social o prepaga'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}