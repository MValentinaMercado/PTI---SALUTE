import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/core/biometric_service.dart';

/// Pantalla de candado genérica: pide la huella antes de mostrar lo que
/// haya detrás. Se usa para proteger secciones sensibles ya adentro de la
/// app (por ejemplo el Diario), no para el login en sí.
class BiometricLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final String title;
  final String subtitle;
  final String authReason;

  /// Texto y acción del botón secundario (ej. "Volver" al dashboard).
  final String cancelLabel;
  final VoidCallback onCancel;

  const BiometricLockScreen({
    super.key,
    required this.onUnlocked,
    required this.onCancel,
    this.title = 'Sección protegida',
    this.subtitle = 'Confirmá tu huella para continuar',
    this.authReason = 'Confirmá tu identidad para continuar',
    this.cancelLabel = 'Volver',
  });

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Dispara el prompt automáticamente al entrar, para no obligar al
    // usuario a tocar un botón extra.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final ok = await BiometricService.instance.authenticate(reason: widget.authReason);

    if (!mounted) return;

    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _checking = false;
        _error = 'No pudimos verificar tu huella. Probá de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: SaluteColors.primaryGreen.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: SaluteColors.primaryGreen,
                    size: 52,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SaluteColors.primaryGreen,
                    fontSize: DsFontSize.h4,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 28),
                if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFCC2929), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                ],
                ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 54), child: FilledButton.icon(
                    onPressed: _checking ? null : _unlock,
                    style: FilledButton.styleFrom(
                      backgroundColor: SaluteColors.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _checking
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                        : const Icon(Icons.fingerprint, color: Colors.white),
                    label: const Text(
                      'Intentar de nuevo',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: widget.onCancel,
                  child: Text(
                    widget.cancelLabel,
                    style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
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