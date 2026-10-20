import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/legal/legal_content.dart';
import 'package:saluteapp/core/services/error_log_service.dart';
import 'package:saluteapp/legal/legal_pdf_service.dart';

/// Aviso de Privacidad + Términos de Servicio.
///
/// - Desde Configuración: `TermsScreen()` (solo lectura).
/// - Desde el registro: `TermsScreen(showAcceptButton: true)`; devuelve
///   `true` por Navigator.pop si el usuario toca "Aceptar términos".
class TermsScreen extends StatefulWidget {
  final bool showAcceptButton;
  const TermsScreen({super.key, this.showAcceptButton = false});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final _privacyKey = GlobalKey();
  final _termsKey = GlobalKey();
  bool _savingPdf = false;

  Future<void> _downloadPdf() async {
    if (_savingPdf) return;
    setState(() => _savingPdf = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await LegalPdfService.instance.savePdf();
      if (location != null) {
        messenger.showSnackBar(const SnackBar(content: Text('PDF guardado.')));
      }
    } catch (e, st) {
      ErrorLog.instance.record(window: 'Términos y Privacidad', error: e, stack: st);
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo guardar el PDF. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: 'SALUTE', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DOCUMENTACIÓN LEGAL',
                      style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: SaluteColors.textMuted, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: const Text(
                        'Privacidad y Términos de Servicio',
                        style: TextStyle(
                          fontSize: 32,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          color: SaluteColors.primaryGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Tu confianza es lo más importante. Acá te explicamos, sin vueltas, '
                          'cómo cuidamos los datos de salud tuyos y de tu familia.',
                      style: TextStyle(fontSize: 15, height: 1.5, color: Colors.grey[800]),
                    ),
                    const SizedBox(height: 22),
                    _JumpCard(
                      icon: Icons.shield_outlined,
                      title: 'Aviso de Privacidad',
                      text: 'Cómo recopilamos, usamos y protegemos tu información.',
                      action: 'Leer aviso completo',
                      onTap: () => _jumpTo(_privacyKey),
                    ),
                    const SizedBox(height: 12),
                    _JumpCard(
                      icon: Icons.gavel_outlined,
                      title: 'Términos de Servicio',
                      text: 'Las reglas de uso de SALUTE para todos los integrantes.',
                      action: 'Explorar términos',
                      onTap: () => _jumpTo(_termsKey),
                    ),
                    const SizedBox(height: 22),
                    _LegalCard(key: _privacyKey, title: 'Aviso de Privacidad', items: kPrivacyItems),
                    const SizedBox(height: 18),
                    _LegalCard(key: _termsKey, title: 'Términos de Servicio', items: kTermsItems),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Última actualización: $kLegalLastUpdate',
                        style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 50), child: OutlinedButton.icon(
                        onPressed: _savingPdf ? null : _downloadPdf,
                        icon: _savingPdf
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_outlined),
                        label: const Text('Descargar en PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SaluteColors.primaryGreen,
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    if (widget.showAcceptButton) ...[
                      const SizedBox(height: 12),
                      ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 54), child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: SaluteColors.primaryGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Aceptar términos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JumpCard extends StatelessWidget {
  final IconData icon;
  final String title, text, action;
  final VoidCallback onTap;
  const _JumpCard({required this.icon, required this.title, required this.text, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: SaluteColors.lightGreen.withValues(alpha: 0.5),
                child: Icon(icon, color: SaluteColors.primaryGreen),
              ),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SaluteColors.primaryGreen)),
              const SizedBox(height: 6),
              Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey[700])),
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(child: Text(action, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SaluteColors.primaryGreen))),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 16, color: SaluteColors.primaryGreen),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalCard extends StatelessWidget {
  final String title;
  final List<LegalItem> items;
  const _LegalCard({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: SaluteColors.primaryGreen)),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      (i + 1).toString().padLeft(2, '0'),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: SaluteColors.darkGreen),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[i].title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SaluteColors.darkGreen)),
                        const SizedBox(height: 6),
                        Text(items[i].body, style: TextStyle(fontSize: 14, height: 1.55, color: Colors.grey[800])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}